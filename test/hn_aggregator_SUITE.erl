-module(hn_aggregator_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("test/include/test_shared.hrl").


-define(HN_AGGREGATOR, "http://localhost:9999/stories/").
-define(HN_API_MOCK_PORT, 9998).

%% API
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

-export([
    read_story_success/1,
    read_story_not_found/1,
    read_stories_pagination_success/1,
    poll_top_stories_timeout/1,
    poll_story_not_found/1
]).

all() -> [
    read_story_success,
    read_story_not_found,
    read_stories_pagination_success,
    poll_top_stories_timeout,
    poll_story_not_found
].

init_per_suite(Config) ->
    Env = [{hn_aggregator, ct:get_config(hn_aggregator)}],
    [application:set_env(hn_aggregator, Key, Val) || {Key, Val} <- proplists:get_value(hn_aggregator, Env)],

    ok = hn_api_mock:start(?HN_API_MOCK_PORT), %% Start the mock HN API server
    timer:sleep(1000),
    {ok, _} = application:ensure_all_started(hn_aggregator), %% Start the HN Aggregator application

    Config.

end_per_suite(_Config) ->
    ok = application:stop(ranch),
    ok = application:stop(cowboy),
    ok = application:stop(hn_aggregator),
    ok.

init_per_testcase(poll_top_stories_timeout, Config) ->
    ok = application:set_env(hn_aggregator, ?HN_API_MOCK_DELAY_KEY, 10000), %% Set the mock delay to 10 seconds
    ok = hn_storage_handler:clear_cache(),
    ok = hn_poller:restart_polling(),
    Config;
init_per_testcase(poll_story_not_found, Config) ->
    ok = application:set_env(hn_aggregator, ?HN_API_MOCK_NOT_FOUND_STORY_ID_KEY, 456),
    ok = hn_storage_handler:clear_cache(),
    ok = hn_poller:restart_polling(),
    Config;
init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(poll_top_stories_timeout, _Config) ->
    ok = application:set_env(hn_aggregator, ?HN_API_MOCK_DELAY_KEY, 0),
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.

%% Test Cases

read_story_success(_Config) ->
    timer:sleep(3000),
    {ok, {{_, 200, _}, _, Resp}} = httpc:request(get, {?HN_AGGREGATOR ++ "456", []}, [], []),
    ct:pal("=======read_story_success===== Response ~p", [Resp]),
    Story = jsone:decode(to_binary(Resp)),
    ct:pal("=======read_story_success===== Story ~p", [Story]),
    ?assert(?STORY_456 =:= Story).

read_story_not_found(_Config) ->
    timer:sleep(3000),
    {ok, {{_, Error, _}, _, Resp}} = httpc:request(get, {?HN_AGGREGATOR ++ "123456789", []}, [], []),
    ct:pal("=======read_story_not_found===== Response ~p", [Resp]),
    ?assert(404 =:= Error).

read_stories_pagination_success(_Config) ->
    timer:sleep(3000),
    {ok, {{_, 200, _}, _, Resp}} = httpc:request(get, {?HN_AGGREGATOR ++ "?page=3", []}, [], []),
    ct:pal("=======read_stories_pagination_success===== Response ~p", [Resp]),
    [Story|_] = jsone:decode(to_binary(Resp)),
    ct:pal("=======read_stories_pagination_success===== Story ~p", [Story]),
    ?assert(?STORY_131415 =:= Story).

poll_top_stories_timeout(_Config) ->
    timer:sleep(30000),
    Stories = hn_storage_handler:read_all_stories(),
    ct:pal("=======poll_top_stories_timeout===== Stories ~p", [Stories]),
    ?assert([] =:= Stories).

poll_story_not_found(_Config) ->
    timer:sleep(10000),
    Stories = hn_storage_handler:read_all_stories(),
    ct:pal("=======poll_story_not_found===== Stories ~p", [Stories]),
    ExpectedStories = lists:filter(fun(#{<<"id">> := Id}) -> Id =/= 456 end, ?STORIES),
    ?assert(ExpectedStories =:= Stories).

%% Internal

to_binary(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_binary(List) when is_list(List) -> list_to_binary(List);
to_binary(Bin) when is_binary(Bin) -> Bin.
