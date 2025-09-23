-module(hn_poller).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").

-export([start_link/0]).

-export([restart_polling/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

restart_polling() ->
    gen_server:cast(?MODULE, restart).

init([]) ->
    {ok, HNApiBaseURL} = application:get_env(hn_aggregator, hn_api_base_url),
    {ok, HNApiTopStoriesPath} = application:get_env(hn_aggregator, hn_api_top_stories_path),
    {ok, HNApiItemPath} = application:get_env(hn_aggregator, hn_api_item_path),
    {ok, PollingRate} = application:get_env(hn_aggregator, polling_rate_ms),
    {ok, TopN} = application:get_env(hn_aggregator, top_n),
    {ok, MaxPollingAttempts} = application:get_env(hn_aggregator, max_polling_attempts),
    {ok, PollingBackOffMS} = application:get_env(hn_aggregator, polling_backoff_ms),
    erlang:send_after(PollingRate, self(), {poll, MaxPollingAttempts}),
    {ok, #{
        hn_api_base_url => HNApiBaseURL,
        hn_api_top_stories_path => HNApiTopStoriesPath,
        hn_api_item_path => HNApiItemPath,
        polling_rate_ms => PollingRate,
        top_n => TopN,
        max_polling_attempts => MaxPollingAttempts,
        used_polling_attempts => 0,
        polling_backoff_ms => PollingBackOffMS
    }}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(
    restart, #{max_polling_attempts := MaxPollingAttempts, polling_rate_ms := PollingRate} = State
) ->
    erlang:send_after(PollingRate, self(), {poll, MaxPollingAttempts}),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

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
                    stories_requests => undefined,
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
    ?LOG_DEBUG("Received Top Stories List: ~p~n", [Body]),
    StoriesRequests = handle_top_stories_list(Body, TopN, HNApiBaseURL ++ "/" ++ HNApiItemPath),
    {noreply, State#{stories_requests => StoriesRequests}};
handle_info(
    {http, {RequestId, {{_, 200, _}, _Headers, Body}}},
    #{
        stories_requests := StoriesRequests,
        polling_rate_ms := PollingRate,
        max_polling_attempts := MaxPollingAttempts
    } = State
) ->
    case lists:keytake(RequestId, 2, StoriesRequests) of
        {value, {SortingOrder, _RequestId}, RemainingStoriesRequests} ->
            ok = handle_story(SortingOrder, Body),
            NewState = State#{stories_requests => RemainingStoriesRequests},
            %% Only restart polling when ALL stories are fetched
            case RemainingStoriesRequests of
                [] ->
                    ?LOG_INFO("All stories fetched successfully. Starting new polling cycle."),
                    erlang:send_after(PollingRate, self(), {poll, MaxPollingAttempts}),
                    {noreply, NewState#{stories_requests => undefined}};
                _ ->
                    ?LOG_DEBUG("~p stories still pending", [length(RemainingStoriesRequests)]),
                    {noreply, NewState}
            end;
        false ->
            ?LOG_WARNING("Received response for unknown request: ~p", [RequestId]),
            {noreply, State}
    end;
handle_info(
    {http, {_RequestId, {{_, Status, _}, _Headers, _Body}}},
    #{
        max_polling_attempts := MaxPollingAttempts,
        polling_rate_ms := PollingRate,
        polling_backoff_ms := PollingBackOffMS,
        used_polling_attempts := UsedPollingAttempts
    } = State
) ->
    {RemainingAttempts, IncreasedPollingRate} = handle_unsuccessful_response_status(
        Status, MaxPollingAttempts, UsedPollingAttempts, PollingRate, PollingBackOffMS
    ),
    %% Restart polling cycle if either of the requests failed (top stories or individual story)
    erlang:send_after(IncreasedPollingRate, self(), {poll, RemainingAttempts}),
    {noreply, State#{
        top_request_id => undefined,
        stories_requests => undefined,
        used_polling_attempts => UsedPollingAttempts + 1,
        polling_rate_ms => IncreasedPollingRate
    }};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_unsuccessful_response_status(
    Status, MaxPollingAttempts, UsedPollingAttempts, PollingRate0, PollingBackOffMS
) ->
    %% TODO: Implement backoff strategy based on status code
    ?LOG_WARNING("Received unsuccessful HTTP status: ~p~n", [Status]),
    RemainingAttempts = MaxPollingAttempts - UsedPollingAttempts - 1,
    PollingRate = PollingRate0 + PollingBackOffMS,
    {RemainingAttempts, PollingRate}.

handle_top_stories_list(Body, TopN, HNApiItemURL) ->
    TopStoriesIdsTotal = jsone:decode(Body),
    {TopStoriesIds, _} = lists:split(TopN, TopStoriesIdsTotal),
    {_, StoriesRequests} = lists:foldl(
        fun(Id, {SortingOrder0, Acc}) ->
            ?LOG_DEBUG("Processing item ID: ~p~n", [Id]),
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

handle_story(SortingOrder, Body) ->
    Story = jsone:decode(Body),
    ?LOG_DEBUG("Received story: ~p~n", [Story]),
    ok = hn_storage_handler:store_story(SortingOrder, Story),
    ok.
