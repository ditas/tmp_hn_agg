%% @doc WebSocket Handler for Real-time Hacker News Stories
%%
%% This module implements a Cowboy WebSocket handler that provides real-time
%% updates of Hacker News top stories to connected clients. It manages WebSocket
%% connections with rate limiting, automatic story updates, and message throttling.
%%
%% The handler implements a push-based architecture where clients receive:
%% - Initial story data upon connection establishment
%% - Automatic updates when new stories are available from the poller
%% - Rate-limited message handling to prevent abuse
%%
%% Features:
%% - Connection-level rate limiting using IP addresses
%% - Per-connection message rate limiting with sliding window
%% - Automatic registration for story update notifications
%% - JSON-encoded story data transmission
%% - Configurable idle timeouts and rate limits
%% - Process group membership for broadcast notifications
%%
%% Connection flow:
%% 1. Client connects and passes IP-based rate limiting
%% 2. Handler joins process group for story update notifications
%% 3. Initial story data is sent to client immediately
%% 4. Handler receives and forwards story updates as they arrive
%% 5. Client messages are rate-limited to prevent spam
%%
%% Configuration:
%% - `max_ws_connections': Max WebSocket connections per IP
%% - `ws_idle_timeout_ms': Connection idle timeout in milliseconds
%% - `top_n': Number of top stories to send (page size)
%% - `ws_rate_limit_window_ms': Message rate limiting window
%% - `ws_rate_limit_msg_max_count': Max messages per rate limit window
%%
%% @end
-module(hn_ws_handler).

-behaviour(cowboy_websocket).

-include("common.hrl").
-include_lib("kernel/include/logger.hrl").

-export([init/2]).
-export([websocket_init/1, websocket_handle/2, websocket_info/2]).

-define(DEFAULT_WS_PAGE_NUM, 1).

-type state() :: #{
    msg_timestamps := [pos_integer()],
    page_size := pos_integer(),
    rate_limit_window_ms := pos_integer(),
    rate_limit_msg_max_count := pos_integer()
}.

-spec init(cowboy_req:req(), any()) -> {cowboy_websocket, cowboy_req:req(), state(), map()}.
init(Req, _Opts) ->
    {IP, Port} = cowboy_req:peer(Req),
    ?LOG_DEBUG("WS: Peer IP: ~p, Port: ~p", [IP, Port]),
    {ok, MaxWSConnections} = application:get_env(
        hn_aggregator, max_ws_connections
    ),
    case hn_rate_limiter:check_connection_rate_limit(IP, MaxWSConnections) of
        allow ->
            {ok, IdleTimeout} = application:get_env(hn_aggregator, ws_idle_timeout_ms),
            {ok, PageSize} = application:get_env(hn_aggregator, top_n),
            {ok, RateLimitWindowMS} = application:get_env(hn_aggregator, ws_rate_limit_window_ms),
            {ok, RateLimitMsgMaxCount} = application:get_env(
                hn_aggregator, ws_rate_limit_msg_max_count
            ),
            {cowboy_websocket, Req,
                #{
                    msg_timestamps => [],
                    page_size => PageSize,
                    rate_limit_window_ms => RateLimitWindowMS,
                    rate_limit_msg_max_count => RateLimitMsgMaxCount
                },
                #{idle_timeout => IdleTimeout}};
        {disallow, RetryAfter} ->
            Req1 = cowboy_req:reply(
                429, #{<<"Retry-After">> => integer_to_binary(RetryAfter)}, Req
            ),
            {stop, Req1, #{}}
    end.

-spec websocket_init(state()) -> {[{text, binary()}], state()}.
websocket_init(#{page_size := PageSize} = State) ->
    ok = pg:join(?DEFAULT_WS_HANDLERS_PG_NAME, self()),
    {ok, Stories} = hn_storage_handler:read_stories(?DEFAULT_WS_PAGE_NUM, PageSize),
    Body = jsone:encode(Stories),
    {[{text, Body}], State}.

-spec websocket_handle(ping | pong | {text | binary | ping | pong, binary()}, state()) ->
    {ok, state()}.
websocket_handle(Data, State) ->
    ?LOG_DEBUG("Received msg from client ~p", [Data]),
    check_msg_rate_limit(State).

-spec websocket_info(stories_updated, state()) -> {ok, map()} | {[{text, binary()}], state()}.
websocket_info(stories_updated, #{page_size := PageSize} = State) ->
    ?LOG_DEBUG("Received update ~p"),
    {ok, Stories} = hn_storage_handler:read_stories(?DEFAULT_WS_PAGE_NUM, PageSize),
    Body = jsone:encode(Stories),
    {[{text, Body}], State};
websocket_info(_Info, State) ->
    {ok, State}.

%% Internal functions

%% @doc Check if client has exceeded message rate limits
%%
%% Implements a sliding window rate limiting algorithm for WebSocket messages:
%% 1. Gets current timestamp and calculates window start time
%% 2. Filters message timestamps to only include those within the window
%% 3. Compares message count against the configured maximum
%% 4. Either allows the message (updating timestamps) or disconnects
%%
%% This prevents clients from overwhelming the server with excessive messages
%% while allowing normal interactive usage patterns.
%%
%% @returns {ok, UpdatedState} to continue, {stop, State} to disconnect
%% @end
-spec check_msg_rate_limit(state()) -> {ok, state()} | {stop, state()}.
check_msg_rate_limit(
    #{
        msg_timestamps := MsgTimestamps,
        rate_limit_window_ms := RateLimitWindowMS,
        rate_limit_msg_max_count := RateLimitMsgMaxCount
    } = State
) ->
    Now = erlang:system_time(millisecond),
    WindowStart = Now - RateLimitWindowMS,
    LatestTimestamps = [Ts || Ts <- MsgTimestamps, Ts >= WindowStart],
    case length(LatestTimestamps) > RateLimitMsgMaxCount of
        true ->
            {stop, State};
        false ->
            {ok, State#{msg_timestamps => [Now | LatestTimestamps]}}
    end.
