-module(hn_api_mock).

-export([
    start/1,
    stop/0
]).

start(HNApiMockPort) ->

    %% -----------------------------EXPERIMENTAL-----------------------------
    SettingsTable = ets:new(hn_api_mock_settings, [named_table, public]),
    %% -----------------------------/-----------------------------

    {ok, _} = application:ensure_all_started([ranch, cowboy]),

    Dispatch = cowboy_router:compile([
        {'_', [
            {"/v0/:top", hn_api_mock_handler, []},
            {"/v0/item/:item", hn_api_mock_handler, []}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(
        http_mock,
        [{port, HNApiMockPort}],
        #{env => #{dispatch => Dispatch}}
    ),

    ct:pal("HN API mock started on port ~p~n", [HNApiMockPort]),

    ok.

stop() ->
    cowboy:stop_listener(http_listener).
