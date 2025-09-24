%%%-------------------------------------------------------------------
%% @doc hn_aggregator top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(hn_aggregator_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
-spec init([]) -> {ok, {#{intensity := 3, period := 10, strategy := one_for_one}, [map(), ...]}}.
init([]) ->
    SupFlags =
        #{
            strategy => one_for_one,
            intensity => 3,
            period => 10
        },
    ChildSpecs = [
        #{
            id => hn_storage_handler,
            start => {hn_storage_handler, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [hn_storage_handler]
        },
        #{
            id => hn_poller,
            start => {hn_poller, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [hn_poller]
        },
        #{
            id => hn_rate_limiter,
            start => {hn_rate_limiter, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [hn_rate_limiter]
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
