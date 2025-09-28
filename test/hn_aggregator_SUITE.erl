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
    % init_per_testcase/2,
    % end_per_testcase/2
]).

-export([
    poll_stories_success/1
]).

all() -> [
    poll_stories_success
].

init_per_suite(Config) ->
    Env = [{hn_aggregator, ct:get_config(hn_aggregator)}],
    [application:set_env(hn_aggregator, Key, Val) || {Key, Val} <- proplists:get_value(hn_aggregator, Env)],

    ok = hn_api_mock:start(?HN_API_MOCK_PORT), %% Start the mock HN API server

    % _ = application:ensure_all_started(hn_aggregator),
    timer:sleep(3000),
    Ping = os:cmd("ping http://localhost:9999/stories"),
    ct:pal("Ping ~p", [Ping]),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(hn_aggregator),
    ok.

% init_per_testcase(poll_stories_success, Config) ->

%     %% TODO: fix me
%     hn_api_mock_state_table = ets:new(hn_api_mock_state_table, [named_table, public]),

%     ok = hn_api_mock:set_response(topstories, ?STORIES_IDS),
%     ok = hn_api_mock:set_response(items, ?STORIES),
%     Config;
% init_per_testcase(_TestCase, Config) ->
%     Config.

% end_per_testcase(_TestCase, _Config) ->
%     ok.

poll_stories_success(_Config) ->
    timer:sleep(30000),
    % {ok, {{_, 200, _}, _, Resp}}
    Resp
    = httpc:request(
        get,
        {?HN_AGGREGATOR ++ "/456", []},
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
