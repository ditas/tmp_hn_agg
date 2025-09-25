-module(hn_ws_handler).

-behaviour(cowboy_websocket).

-include("common.hrl").
-include_lib("kernel/include/logger.hrl").

-export([init/2]).
-export([websocket_init/1, websocket_handle/2, websocket_info/2, terminate/3]).

-define(DEFAULT_WS_PAGE_SIZE, 50).
-define(DEFAULT_WS_PAGE_NUM, 1).
-define(DEFAULT_IDLE_TIMEOUT_MS, 60000).
-define(DEFAULT_WS_RATE_LIMIT_WINDOW_MS, 10000).
-define(DEFAULT_WS_RATE_LIMIT_MSG_MAX_COUNT, 5).

-spec init(cowboy_req:req(), map()) -> {cowboy_websocket, cowboy_req:req(), map(), map()}.
init(Req, _Opts) ->
    {IP, Port} = cowboy_req:peer(Req),
    ?LOG_DEBUG("WS: Peer IP: ~p, Port: ~p", [IP, Port]),
    {ok, MaxWSConnectionsPerMinute} = application:get_env(
        hn_aggregator, max_ws_connections_per_minute
    ),
    State = #{last_msg_mtime => erlang:monotonic_time(millisecond), msg_count => 0},
    case hn_rate_limiter:check_rate_limit(IP, MaxWSConnectionsPerMinute) of
        allow ->
            {cowboy_websocket, Req, State, #{idle_timeout => ?DEFAULT_IDLE_TIMEOUT_MS}};
        {disallow, RetryAfter} ->
            Req1 = cowboy_req:reply(
                429, #{<<"Retry-After">> => integer_to_binary(RetryAfter)}, Req
            ),
            {stop, Req1, State}
    end.

-spec websocket_init(map()) -> {[{text, binary()}], map()}.
websocket_init(State) ->
    ok = pg:join(?DEFAULT_WS_HANDLERS_PG_NAME, self()),
    {ok, Stories} = hn_storage_handler:read_stories(?DEFAULT_WS_PAGE_NUM, ?DEFAULT_WS_PAGE_SIZE),
    Body = jsone:encode(Stories),
    {[{text, Body}], State}.

-spec websocket_handle(ping | pong | {text | binary | ping | pong, binary()}, map()) -> {ok, map()}.
websocket_handle(Data, #{last_msg_mtime := LastMsgMTime, msg_count := MsgCount0} = State) ->
    ?LOG_DEBUG("Received msg from client ~p", [Data]),
    Now = erlang:monotonic_time(millisecond),
    NewMsgCount =
        case
            Now - LastMsgMTime < ?DEFAULT_WS_RATE_LIMIT_WINDOW_MS andalso
                MsgCount0 > ?DEFAULT_WS_RATE_LIMIT_MSG_MAX_COUNT
        of
            true -> {stop, State};
            false -> MsgCount0 + 1
        end,
    {ok, State#{last_msg_mtime => Now, msg_count => NewMsgCount}}.

-spec websocket_info(stories_updated, map()) -> {ok, map()} | {[{text, binary()}], map()}.
websocket_info(stories_updated, State) ->
    ?LOG_DEBUG("Received update ~p"),
    {ok, Stories} = hn_storage_handler:read_stories(?DEFAULT_WS_PAGE_NUM, ?DEFAULT_WS_PAGE_SIZE),
    Body = jsone:encode(Stories),
    {[{text, Body}], State};
websocket_info(_Info, State) ->
    {ok, State}.

-spec terminate(_Reason, _Req, _State) -> ok.
terminate(_Reason, _Req, _State) ->
    ok.

%% Internal functions
