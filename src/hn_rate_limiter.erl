%% @doc Rate Limiter for HTTP/WebSocket Connections
%%
%% This module implements a gen_server that provides rate limiting functionality
%% for WebSocket connections based on client IP addresses. It uses a fixed
%% time window approach to track connection attempts and enforce limits.
%%
%% The rate limiter maintains an ETS table to store connection counts per IP
%% address within time windows. It automatically cleans up expired entries
%% to prevent memory leaks and ensure accurate rate limiting.
%%
%% Features:
%% - IP-based rate limiting with configurable thresholds
%% - Automatic cleanup of expired rate limit entries
%%
%% Configuration:
%% - `rate_limit_cleanup_timeout_ms': Interval for cleaning up expired entries
%%
%% @end
-module(hn_rate_limiter).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").

-export([start_link/0]).

-export([check_connection_rate_limit/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-type state() :: #{rate_limit_cleanup_timeout_ms := non_neg_integer()}.

-define(RATE_LIMIT_TABLE, rate_limit).
-define(DEFAULT_TIME_WINDOW_SEC, 60).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Check if a connection from the given IP should be allowed
%%
%% Each IP address is allowed up to MaxRequests connections within a 60-second time window.
%% The function increments the connection count and returns whether the
%% connection should be allowed or denied.
%%
%% Time windows are calculated by dividing the current timestamp by the
%% window size, creating discrete 60-second periods. Old entries are
%% cleaned up periodically by a background process.
%%
%% @param IP The client's IP address
%% @param MaxRequests Maximum allowed connections per time window
%% @returns `allow' if under the limit, `{disallow, SecondsLeft}' if over
%% @end
-spec check_connection_rate_limit(inet:ip_address(), non_neg_integer()) ->
    allow | {disallow, non_neg_integer()}.
check_connection_rate_limit(IP, MaxRequests) ->
    TimeWindow = erlang:system_time(second) div ?DEFAULT_TIME_WINDOW_SEC,
    Count0 =
        case ets:lookup(?RATE_LIMIT_TABLE, {IP, TimeWindow}) of
            [] -> 0;
            [{_, C}] -> C
        end,
    Count = Count0 + 1,
    ets:insert(?RATE_LIMIT_TABLE, {{IP, TimeWindow}, Count}),
    ?LOG_DEBUG("Rate limit count for ~p: ~p", [{IP, TimeWindow}, Count]),
    case Count =< MaxRequests of
        true ->
            allow;
        false ->
            SecondsLeft =
                ?DEFAULT_TIME_WINDOW_SEC -
                    (erlang:system_time(second) rem ?DEFAULT_TIME_WINDOW_SEC),
            {disallow, SecondsLeft}
    end.

-spec init([]) -> {ok, state()}.
init([]) ->
    _ = ets:new(?RATE_LIMIT_TABLE, [named_table, public]),
    {ok, RateLimitCleanupTimeout} = application:get_env(
        hn_aggregator, rate_limit_cleanup_timeout_ms
    ),
    erlang:send_after(RateLimitCleanupTimeout, ?MODULE, cleanup),
    {ok, #{rate_limit_cleanup_timeout_ms => RateLimitCleanupTimeout}}.

-spec handle_call(any(), any(), state()) -> {reply, ok, state()}.
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(cleanup, #{rate_limit_cleanup_timeout_ms := RateLimitCleanupTimeout} = State) ->
    TimeWindow = erlang:system_time(second) div ?DEFAULT_TIME_WINDOW_SEC,
    ets:select_delete(?RATE_LIMIT_TABLE, [
        {{{'_', '$1'}, '_'}, [{'<', '$1', TimeWindow}], [true]}
    ]),
    erlang:send_after(RateLimitCleanupTimeout, ?MODULE, cleanup),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(any(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(any(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
