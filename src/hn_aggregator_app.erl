%%%-------------------------------------------------------------------
%% @doc hn_aggregator public API
%% @end
%%%-------------------------------------------------------------------

-module(hn_aggregator_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/stories", hn_http_handler, []},
            {"/stories/:id", hn_http_handler, []},
            {"/ws", hn_ws_handler, []}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(
        http_listener,
        [{port, 8080}],
        #{env => #{dispatch => Dispatch}}
    ),
    hn_aggregator_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
