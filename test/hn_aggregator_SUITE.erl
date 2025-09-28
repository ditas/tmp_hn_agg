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
    end_per_suite/1
]).

-export([
    read_story_success/1,
    read_story_not_found/1,
    read_stories_pagination_success/1
]).

all() -> [
    read_story_success,
    read_story_not_found,
    read_stories_pagination_success
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

read_story_success(_Config) ->
    timer:sleep(3000),
    {ok, {{_, 200, _}, _, Resp}} = httpc:request(get, {?HN_AGGREGATOR ++ "456", []}, [], []),
    ct:pal("=======poll_stories_success===== Response ~p", [Resp]),
    Story = jsone:decode(to_binary(Resp)),
    ct:pal("=======poll_stories_success===== Story ~p", [Story]),
    ?assert(?STORY_456 =:= Story).

read_story_not_found(_Config) ->
    timer:sleep(3000),
    {ok, {{_, Error, _}, _, Resp}} = httpc:request(get, {?HN_AGGREGATOR ++ "123456789", []}, [], []),
    ct:pal("=======poll_stories_not_found===== Response ~p", [Resp]),
    ?assert(404 =:= Error).

read_stories_pagination_success(_Config) ->
    timer:sleep(3000),
    {ok, {{_, 200, _}, _, Resp}} = httpc:request(get, {?HN_AGGREGATOR ++ "?page=3", []}, [], []),
    ct:pal("=======poll_stories_pagination===== Response ~p", [Resp]),
    [Story|_] = jsone:decode(to_binary(Resp)),
    ct:pal("=======poll_stories_pagination===== Story ~p", [Story]),
    ?assert(?STORY_131415 =:= Story).

poll_top_stories_fail(_Config) ->
    ok.

%% Internal

to_binary(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_binary(List) when is_list(List) -> list_to_binary(List);
to_binary(Bin) when is_binary(Bin) -> Bin.
