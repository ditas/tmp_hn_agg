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
