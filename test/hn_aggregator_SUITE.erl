-module(hn_aggregator_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").


-define(HN_AGGREGATOR, "http://localhost:9999/stories/").
-define(HN_API_MOCK_PORT, 9998).

%% API
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1
]).

-export([
    poll_stories_success/1
]).

all() -> [
    poll_stories_success
].

init_per_suite(Config) ->
    % timer:sleep(5000),
    % ok = application:stop(hn_aggregator),

    Env = [{hn_aggregator, ct:get_config(hn_aggregator)}],
    [application:set_env(hn_aggregator, Key, Val) || {Key, Val} <- proplists:get_value(hn_aggregator, Env)],

    ok = application:start(sasl),
    ok = application:start(jsone),
    ok = application:start(observer),

    ok = hn_api_mock:start(?HN_API_MOCK_PORT), %% Start the mock HN API server

    {ok, _} = application:ensure_all_started(hn_aggregator),

    timer:sleep(3000),
    Ping = os:cmd("ping http://localhost:9999/stories"),
    ct:pal("Ping ~p", [Ping]),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(hn_aggregator),
    ok.

poll_stories_success(_Config) ->
    timer:sleep(30000),
    % {ok, {{_, 200, _}, _, Resp}}
    Resp
    = httpc:request(
        get,
        {?HN_AGGREGATOR ++ "456", []},
        [],
        []
    ),
    ct:pal("--------------Resp ~p", [Resp]),
    % ?assert(Story =:= #{
    %     <<"by">> => <<"test1">>,
    %     <<"descendants">> => 1,
    %     <<"id">> => 123,
    %     <<"kids">> => [],
    %     <<"score">> => 155,
    %     <<"time">> => 1758828112,
    %     <<"title">> => <<"Test1 Title">>,
    %     <<"type">> => <<"story">>,
    %     <<"url">> => <<"https://test1.com">>
    % }).
    ok.
