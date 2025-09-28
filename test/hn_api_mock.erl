-module(hn_api_mock).

-export([
    start/1,
    set_response/2,
    set_delay/1,
    set_error/1,
    reset_state/0,
    stop/0
]).

-define(HN_API_MOCK_STATE_TABLE, hn_api_mock_state_table).

start(HNApiMockPort) ->
    {ok, _} = application:ensure_all_started([ranch, cowboy]),

    Dispatch = cowboy_router:compile([
        {'_', [
            {"/v0/:top", hn_api_mock_handler, []},
            {"/v0/item/:item", hn_api_mock_handler, []}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(
        http_listener,
        [{port, HNApiMockPort}],
        #{env => #{dispatch => Dispatch}}
    ),

    ct:pal("HN API mock started on port ~p~n", [HNApiMockPort]),

    ok.

stop() ->
    cowboy:stop_listener(http_listener).

set_response(Type, Response) ->
    true = ets:insert(?HN_API_MOCK_STATE_TABLE, {Type, Response}),
    ok.

set_delay(DelayMS) ->
    true = ets:insert(?HN_API_MOCK_STATE_TABLE, {delay, DelayMS}),
    ok.

set_error(Error) ->
    true = ets:insert(?HN_API_MOCK_STATE_TABLE, {error, Error}),
    ok.

reset_state() ->
    true = ets:delete_all_objects(?HN_API_MOCK_STATE_TABLE),
    ok.
