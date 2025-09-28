%%%-------------------------------------------------------------------
%% @doc hn_aggregator public API
%% @end
%%%-------------------------------------------------------------------

-module(hn_aggregator_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(any(), any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    {ok, Port} = application:get_env(hn_aggregator, port),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/stories", hn_http_handler, []},
            {"/stories/:id", hn_http_handler, []},
            {"/ws", hn_ws_handler, []}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(
        hn_aggregator_http,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ),
    hn_aggregator_sup:start_link().

-spec stop(any()) -> ok.
stop(_State) ->
    ok.

%% internal functions
