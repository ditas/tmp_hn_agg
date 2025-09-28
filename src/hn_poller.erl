-module(hn_poller).

-behaviour(gen_server).

-include("common.hrl").
-include_lib("kernel/include/logger.hrl").

-export([start_link/0]).

-export([restart_polling/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-type state() :: #{
    hn_api_base_url := string(),
    hn_api_top_stories_path := string(),
    hn_api_item_path := string(),
    polling_rate_ms := pos_integer(),
    top_n := pos_integer(),
    max_polling_attempts := pos_integer(),
    used_polling_attempts := non_neg_integer(),
    polling_backoff_ms := pos_integer(),
    stories := [map()],
    stories_requests := [tuple()] | undefined
}.

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec restart_polling() -> ok.
restart_polling() ->
    gen_server:cast(?MODULE, restart).

-spec init([]) -> {ok, state()}.
init([]) ->
    {ok, HNApiBaseURL} = application:get_env(hn_aggregator, hn_api_base_url),
    {ok, HNApiTopStoriesPath} = application:get_env(hn_aggregator, hn_api_top_stories_path),
    {ok, HNApiItemPath} = application:get_env(hn_aggregator, hn_api_item_path),
    {ok, PollingRate} = application:get_env(hn_aggregator, polling_rate_ms),
    {ok, TopN} = application:get_env(hn_aggregator, top_n),
    {ok, MaxPollingAttempts} = application:get_env(hn_aggregator, max_polling_attempts),
    {ok, PollingBackOffMS} = application:get_env(hn_aggregator, polling_backoff_ms),
    %% Start polling immediately on init
    erlang:send(self(), {poll, MaxPollingAttempts}),
    {ok, #{
        hn_api_base_url => HNApiBaseURL,
        hn_api_top_stories_path => HNApiTopStoriesPath,
        hn_api_item_path => HNApiItemPath,
        polling_rate_ms => PollingRate,
        top_n => TopN,
        max_polling_attempts => MaxPollingAttempts,
        used_polling_attempts => 0,
        polling_backoff_ms => PollingBackOffMS,
        stories => [],
        stories_requests => undefined
    }}.

-spec handle_call(any(), any(), state()) -> {reply, any(), state()}.
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(
    restart, #{max_polling_attempts := MaxPollingAttempts} = State
) ->
    erlang:send(self(), {poll, MaxPollingAttempts}),
    {noreply, State#{
        used_polling_attempts => 0, stories_requests => [], top_request_id => undefined
    }};
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(
    {poll, RemainingAttempts},
    #{
        hn_api_base_url := HNApiBaseURL,
        hn_api_top_stories_path := HNApiTopStoriesPath
    } = State0
) ->
    ?LOG_DEBUG("State on Poll ~p", [State0]),
    ?LOG_DEBUG("Remaining attempts ~p", [RemainingAttempts]),
    State =
        case RemainingAttempts > 0 of
            true ->
                {ok, RequestId} = httpc:request(
                    get,
                    {HNApiBaseURL ++ "/" ++ HNApiTopStoriesPath, [{"Accept", "application/json"}]},
                    [{timeout, 5000}],
                    [{sync, false}, {receiver, self()}]
                ),
                State0#{top_request_id => RequestId};
            false ->
                %% Stop polling when max attempts reached
                %% Use restart_polling/0 to restart polling manually
                ?LOG_WARNING("Max polling attempts reached. Stopping polling."),
                State0#{
                    top_request_id => undefined,
                    stories_requests => [],
                    used_polling_attempts => 0
                }
        end,
    {noreply, State};
handle_info(
    {http, {RequestId, {{_, 200, _}, _Headers, Body}}},
    #{
        hn_api_base_url := HNApiBaseURL,
        top_request_id := RequestId,
        hn_api_item_path := HNApiItemPath,
        top_n := TopN
    } = State
) ->
    StoriesRequests = handle_top_stories_list(Body, TopN, HNApiBaseURL ++ "/" ++ HNApiItemPath),
    {noreply, State#{stories_requests => StoriesRequests}};
handle_info(
    {http, {RequestId, {{_, 200, _}, _Headers, Body}}},
    #{
        stories_requests := StoriesRequests,
        polling_rate_ms := PollingRate,
        max_polling_attempts := MaxPollingAttempts,
        stories := Stories
    } = State
) ->
    case lists:keytake(RequestId, 2, StoriesRequests) of
        {value, {SortingOrder, _RequestId}, RemainingStoriesRequests} ->
            State1 = State#{
                stories => [handle_story(Body, SortingOrder) | Stories],
                stories_requests => RemainingStoriesRequests
            },
            %% Only restart polling when ALL stories are fetched
            case RemainingStoriesRequests of
                [] ->
                    ?LOG_DEBUG("All stories fetched successfully. Starting new polling cycle."),
                    State2 = handle_stories(State1),
                    erlang:send_after(PollingRate, self(), {poll, MaxPollingAttempts}),
                    {noreply, State2};
                _ ->
                    ?LOG_DEBUG("~p stories still pending", [length(RemainingStoriesRequests)]),
                    {noreply, State1}
            end;
        false ->
            ?LOG_WARNING("Received response for unknown request: ~p", [RequestId]),
            {noreply, State}
    end;
handle_info({http, {RequestId, Error}}, #{used_polling_attempts := UsedPollingAttempts} = State0) ->
    ?LOG_WARNING("Received error response: ~p", [Error]),
    {RemainingAttempts, IncreasedPollingRate, State} = handle_failed_request(
        RequestId, Error, State0
    ),
    %% Restart polling cycle if top stories requests failed. Allow individual stories requests to fail without restarting the cycle.
    erlang:send_after(IncreasedPollingRate, self(), {poll, RemainingAttempts}),
    {noreply, State#{
        used_polling_attempts => UsedPollingAttempts + 1,
        polling_rate_ms => IncreasedPollingRate
    }}.

-spec terminate(any(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(any(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal
-spec handle_failed_request(any(), any(), state()) -> {integer(), pos_integer(), state()}.
handle_failed_request(
    RequestId,
    Error,
    #{max_polling_attempts := MaxPollingAttempts, used_polling_attempts := UsedPollingAttempts} =
        State
) ->
    RemainingAttempts = MaxPollingAttempts - UsedPollingAttempts - 1,
    handle_failed_request(RequestId, Error, RemainingAttempts, State).

-spec handle_failed_request(any(), any(), integer(), state()) ->
    {integer(), pos_integer(), state()}.
handle_failed_request(
    RequestId,
    Error,
    RemainingAttempts,
    #{
        top_request_id := RequestId,
        max_polling_attempts := MaxPollingAttempts,
        polling_rate_ms := PollingRate0,
        polling_backoff_ms := PollingBackOffMS
    } = State
) ->
    ?LOG_WARNING("Top Stories Request failed with: ~p; Attempts remains: ~p", [
        Error, RemainingAttempts
    ]),
    PollingRate = PollingRate0 + (PollingBackOffMS * (MaxPollingAttempts - RemainingAttempts)),
    {RemainingAttempts, PollingRate, State#{top_request_id => undefined}};
handle_failed_request(
    RequestId,
    Error,
    RemainingAttempts,
    #{polling_rate_ms := PollingRate, stories_requests := Requests0} = State
) ->
    case lists:keytake(RequestId, 2, Requests0) of
        {value, _, Requests} ->
            ?LOG_WARNING("One of Stories Request failed with: ~p", [Error]),
            {RemainingAttempts, PollingRate, State#{stories_requests => Requests}};
        false ->
            ?LOG_WARNING("Unknown Request failed with: ~p", [Error]),
            {RemainingAttempts, PollingRate, State}
    end.

-spec handle_top_stories_list(binary(), pos_integer(), string()) ->
    [{pos_integer(), reference()}].
handle_top_stories_list(Body, TopN, HNApiItemURL) ->
    TopStoriesIdsTotal = jsone:decode(Body),
    {TopStoriesIds, _} = lists:split(TopN, TopStoriesIdsTotal),
    ?LOG_DEBUG("Received Top Stories List ~p", [length(TopStoriesIds)]),
    {_, StoriesRequests} = lists:foldl(
        fun(Id, {SortingOrder0, Acc}) ->
            ?LOG_DEBUG("Processing item ID: ~p", [Id]),
            {ok, RequestId1} = httpc:request(
                get,
                {HNApiItemURL ++ "/" ++ integer_to_list(Id) ++ ".json", [
                    {"Accept", "application/json"}
                ]},
                [{timeout, 5000}],
                [{sync, false}, {receiver, self()}]
            ),
            SortingOrder = SortingOrder0 + 1,
            {SortingOrder, [{SortingOrder, RequestId1} | Acc]}
        end,
        {0, []},
        TopStoriesIds
    ),
    StoriesRequests.

-spec handle_story(binary(), pos_integer()) -> {pos_integer(), map()}.
handle_story(Body, SortingOrder) ->
    Story = jsone:decode(Body),
    ?LOG_DEBUG("Received story: ~p", [Story]),
    {SortingOrder, Story}.

-spec handle_stories(state()) -> state().
handle_stories(#{stories := Stories} = State) ->
    _ = notify_ws_handlers(),
    hn_storage_handler:store_stories(Stories),
    State#{stories => [], stories_requests => []}.

-spec notify_ws_handlers() -> [stories_updated].
notify_ws_handlers() ->
    Members = pg:get_members(?DEFAULT_WS_HANDLERS_PG_NAME),
    ?LOG_DEBUG("Notifying ~p websocket handlers", [Members]),
    [Pid ! stories_updated || Pid <- Members].
