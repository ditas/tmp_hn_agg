-module(hn_rate_limiter).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").

-export([start_link/0]).

-export([check_rate_limit/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-type state() :: map().

-define(DEFAULT_RATE_LIMIT_TABLE, rate_limit).
%% 1 minute
-define(DEFAULT_RATE_LIMIT_TIMEOUT_MS, 60000).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    erlang:send_after(?DEFAULT_RATE_LIMIT_TIMEOUT_MS, ?MODULE, cleanup),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec check_rate_limit(inet:ip_address(), non_neg_integer()) -> false | {true, non_neg_integer()}.
check_rate_limit(IP, MaxRequestsPerMinute) ->
    Minute = erlang:system_time(second) div 60,
    Count =
        case ets:lookup(?DEFAULT_RATE_LIMIT_TABLE, {IP, Minute}) of
            [] ->
                0;
            [{_, C}] ->
                C
        end,
    NewCount = Count + 1,
    ets:insert(?DEFAULT_RATE_LIMIT_TABLE, {{IP, Minute}, NewCount}),
    ?LOG_DEBUG("Rate limit count for ~p: ~p", [{IP, Minute}, NewCount]),
    case NewCount =< MaxRequestsPerMinute of
        true ->
            false;
        false ->
            SecondsLeft = 60 - (erlang:system_time(second) rem 60),
            {true, SecondsLeft * 1000}
    end.

-spec init([]) -> {ok, #{}}.
init([]) ->
    _ = ets:new(?DEFAULT_RATE_LIMIT_TABLE, [named_table, public]),
    {ok, #{}}.

-spec handle_call(any(), any(), state()) -> {reply, ok, state()}.
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(cleanup, State) ->
    Minute = erlang:system_time(second) div 60,
    ets:select_delete(?DEFAULT_RATE_LIMIT_TABLE, [
        {{{'_', '$1'}, '_'}, [{'<', '$1', Minute}], [true]}
    ]),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(any(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(any(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
