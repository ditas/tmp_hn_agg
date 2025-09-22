-module(hn_poller).

-behaviour(gen_server).

-include("common.hrl").
-include_lib("kernel/include/logger.hrl").

-export([start_link/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, HNApiBaseURL} = application:get_env(hn_aggregator, hn_api_base_url),
    {ok, HNApiTopStoriesPath} = application:get_env(hn_aggregator, hn_api_top_stories_path),
    {ok, HNApiItemPath} = application:get_env(hn_aggregator, hn_api_item_path),
    {ok, PollingRate} = application:get_env(hn_aggregator, polling_rate_ms),
    {ok, TopN} = application:get_env(hn_aggregator, top_n),
    erlang:send_after(PollingRate, self(), poll),
    {ok, #{
        hn_api_base_url => HNApiBaseURL,
        hn_api_top_stories_path => HNApiTopStoriesPath,
        hn_api_item_path => HNApiItemPath,
        polling_rate_ms => PollingRate,
        top_n => TopN
    }}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(
    poll, #{hn_api_base_url := HNApiBaseURL, hn_api_top_stories_path := HNApiTopStoriesPath} = State
) ->
    {ok, RequestId} = httpc:request(
        get,
        {HNApiBaseURL ++ "/" ++ HNApiTopStoriesPath, [{"Accept", "application/json"}]},
        [{timeout, 5000}],
        [{sync, false}, {receiver, self()}]
    ),
    {noreply, State#{top_request_id => RequestId}};
handle_info(
    {http, {RequestId, {_Status, _Headers, Body}}},
    #{
        hn_api_base_url := HNApiBaseURL,
        top_request_id := RequestId,
        hn_api_item_path := HNApiItemPath,
        top_n := TopN
    } = State
) ->
    ?LOG_DEBUG("Received HTTP response: ~p~n", [Body]),
    TopStoriesIdsTotal = jsone:decode(Body),
    {TopStoriesIds, _} = lists:split(TopN, TopStoriesIdsTotal),
    {_, StoriesRequests} = lists:foldl(
        fun(Id, {SortingOrder0, Acc}) ->
            ?LOG_DEBUG("Processing item ID: ~p~n", [Id]),
            {ok, RequestId1} = httpc:request(
                get,
                {HNApiBaseURL ++ "/" ++ HNApiItemPath ++ "/" ++ integer_to_list(Id) ++ ".json", [
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
    {noreply, State#{stories_requests => StoriesRequests}};
handle_info(
    {http, {RequestId, {_Status, _Headers, Body}}},
    #{stories_requests := StoriesRequests} = State
) ->
    case lists:keyfind(RequestId, 2, StoriesRequests) of
        {SortingOrder, _RequestId} ->
            ok = handle_story(SortingOrder, Body),
            {noreply, State};
        false ->
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_story(SortingOrder, Body) ->
    Story = jsone:decode(Body),
    ?LOG_DEBUG("Received story: ~p~n", [Story]),
    true = ets:insert(?DEFAULT_STORIES_TABLE, {SortingOrder, Story}),
    ok.
