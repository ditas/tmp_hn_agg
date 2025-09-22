%%%-------------------------------------------------------------------
%% @doc hn_aggregator public API
%% @end
%%%-------------------------------------------------------------------

-module(hn_aggregator_app).

-behaviour(application).

-include("common.hrl").

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ets:new(?DEFAULT_STORIES_TABLE, [named_table, public, ordered_set]),
    hn_aggregator_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
