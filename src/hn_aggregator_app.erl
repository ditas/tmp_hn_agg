%%%-------------------------------------------------------------------
%% @doc hn_aggregator public API
%% @end
%%%-------------------------------------------------------------------

-module(hn_aggregator_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    hn_aggregator_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
