-module(hn_aggregator_SUITE).

-include_lib("common_test/include/ct.hrl").

%% API
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1
]).

-export([]).

all() -> [].

init_per_suite(Config) ->
    application:start(inets),
    {ok, _Pid} = inets:start(httpc, [{profile, none}]),
    Config.

end_per_suite(_Config) ->
    ok.
