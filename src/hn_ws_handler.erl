-module(hn_ws_handler).

-behaviour(cowboy_websocket).

-include("common.hrl").
-include_lib("kernel/include/logger.hrl").

-export([init/2]).
-export([websocket_init/1, websocket_handle/2, websocket_info/2, terminate/3]).

-define(DEFAULT_WS_PAGE_SIZE, 50).
-define(DEFAULT_WS_PAGE_NUM, 1).
-define(DEFAULT_IDLE_TIMEOUT_MS, 60000).

init(Req, _Opts) ->
    {cowboy_websocket, Req, #{}, #{idle_timeout => ?DEFAULT_IDLE_TIMEOUT_MS}}.

websocket_init(State) ->
    ok = pg:join(?DEFAULT_WS_HANDLERS_PG_NAME, self()),
    {ok, Stories} = hn_storage_handler:read_stories(?DEFAULT_WS_PAGE_NUM, ?DEFAULT_WS_PAGE_SIZE),
    Body = jsone:encode(Stories),
    {[{text, Body}], State}.

websocket_handle(Data, State) ->
    ?LOG_DEBUG("----------------------Received something from client ~p", [Data]),
    {ok, State}.

websocket_info(stories_updated, State) ->
    ?LOG_DEBUG("----------------------Received update ~p"),
    {ok, Stories} = hn_storage_handler:read_stories(?DEFAULT_WS_PAGE_NUM, ?DEFAULT_WS_PAGE_SIZE),
    Body = jsone:encode(Stories),
    {[{text, Body}], State};
websocket_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _Req, _State) ->
    ok.

%% Internal functions
