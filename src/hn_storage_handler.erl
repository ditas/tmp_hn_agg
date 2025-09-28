%% @doc Hacker News Stories Storage Handler
%%
%% This module implements a gen_server that manages the storage and retrieval
%% of Hacker News stories using ETS tables. It provides a dual-table architecture
%% for efficient story management:
%%
%% 1. Stories Table: Stores stories with their ranking order as keys
%% 2. Sorting Table: Maps story IDs to their ranking positions
%%
%% The dual-table approach enables:
%% - Fast paginated retrieval by ranking order
%% - Quick lookups by story ID
%% - Efficient batch storage operations
%% - Automatic sorting preservation from the HN API
%%
%% Storage Structure:
%% - Stories Table: {Order, StoryMap} where Order is the ranking position
%% - Sorting Table: {StoryId, Order} for reverse lookups
%%
%% The module supports pagination for large story sets and provides debug
%% functionality for cache management during development and testing.
%%
%% @end
-module(hn_storage_handler).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").

-export([start_link/0]).

-export([store_stories/1]).
-export([read_stories/2, read_story_by_id/1]).

%% Debug API
-export([clear_cache/0, read_all_stories/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(STORIES_TABLE, stories).
-define(SORTING_TABLE, sorting).

-type state() :: map().

%% API
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Store a list of stories with their ranking order
%%
%% Asynchronously stores stories in both ETS tables. Each story should
%% be a tuple of {Order, StoryMap} where Order represents the ranking
%% position from the Hacker News top stories list.
%%
%% The function updates both tables:
%% - Stories table gets {Order, StoryMap} entries
%% - Sorting table gets {StoryId, Order} mappings for reverse lookups
%%
%% @returns ok (asynchronous operation)
%% @end
-spec store_stories(list()) -> ok.
store_stories(Stories) ->
    gen_server:cast(?MODULE, {store_stories, Stories}).

%% @doc Read paginated stories by ranking order
%%
%% Retrieves a page of stories based on their ranking order from the
%% Hacker News top stories list. Uses ETS select with range conditions
%% for efficient pagination without loading all stories into memory.
%%
%% Page numbering is 1-based. The function calculates the appropriate
%% offset and range for the ETS select operation.
%%
%% @returns {ok, [StoryMap]} List of story maps in ranking order
%% @end
-spec read_stories(non_neg_integer(), pos_integer()) -> {ok, list()}.
read_stories(PageNum, PageSize) ->
    Offset = (PageNum - 1) * PageSize,
    Range = Offset + PageSize,
    Stories = ets:select(?STORIES_TABLE, [
        {{'$1', '$2'}, [{'>', '$1', Offset}, {'=<', '$1', Range}], [{{'$1', '$2'}}]}
    ]),
    {ok, [Story || {_, Story} <- Stories]}.

%% @doc Read a specific story by its Hacker News ID
%%
%% Performs a two-step lookup to find a story by its ID:
%% 1. Look up the story ID in the sorting table to get its order
%% 2. Look up the order in the stories table to get the full story
%%
%% This dual-lookup approach maintains both fast ID-based access and
%% efficient pagination by ranking order.
%%
%% @returns {ok, StoryMap} if found, {error, not_found} if not found
%% @end
-spec read_story_by_id(pos_integer()) -> {ok, map()} | {error, term()}.
read_story_by_id(Id) ->
    case ets:lookup(?SORTING_TABLE, Id) of
        [] ->
            {error, not_found};
        [{_, Order}] ->
            case ets:lookup(?STORIES_TABLE, Order) of
                [] -> {error, not_found};
                [{_, Story}] -> {ok, Story}
            end
    end.

%% @doc Clear all stored stories from cache (debug function)
%%
%% Removes all entries from both ETS tables. This is primarily used
%% for debugging and testing purposes to reset the storage state.
%%
%% @returns ok (asynchronous operation)
%% @end
-spec clear_cache() -> ok.
clear_cache() ->
    gen_server:cast(?MODULE, clear_cache).

%% @doc Read all stories from cache (debug function)
%%
%% Returns all stories currently stored in the cache. This function
%% loads the entire stories table into memory and should only be used
%% for debugging and testing purposes.
%%
%% @returns List of all story maps (order information is discarded)
%% @end
-spec read_all_stories() -> [{pos_integer(), map()}].
read_all_stories() ->
    Data = ets:tab2list(?STORIES_TABLE),
    [Story || {_Order, Story} <- Data].

-spec init([]) -> {ok, #{}}.
init([]) ->
    ok = create_story_table(),
    ok = create_sorting_table(),
    {ok, #{}}.

-spec handle_call(any(), any(), state()) -> {reply, any(), state()}.
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast({store_stories, Stories}, State) ->
    ?LOG_DEBUG("Storing stories: ~p", [Stories]),
    true = ets:insert(?STORIES_TABLE, Stories),
    IdsOrders = lists:foldl(
        fun({Order, #{<<"id">> := Id}}, Acc) ->
            [{Id, Order} | Acc]
        end,
        [],
        Stories
    ),
    ?LOG_DEBUG("Storing id-to-order mappings: ~p", [IdsOrders]),
    true = ets:insert(?SORTING_TABLE, IdsOrders),
    {noreply, State};
handle_cast(clear_cache, State) ->
    true = ets:delete_all_objects(?STORIES_TABLE),
    true = ets:delete_all_objects(?SORTING_TABLE),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(any(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(any(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal

%% @doc Create the stories ETS table if it doesn't exist
%%
%% Creates an ordered_set table for efficient range queries during
%% pagination. The ordered_set type ensures stories are stored in
%% ranking order, enabling fast pagination without sorting overhead.
%%
%% Table structure: {Order, StoryMap}
%% - Order: Ranking position from HN top stories API
%% - StoryMap: Complete story data from HN item API
%%
%% @returns ok
%% @end
-spec create_story_table() -> ok.
create_story_table() ->
    case ets:info(?STORIES_TABLE) of
        undefined ->
            ?STORIES_TABLE = ets:new(?STORIES_TABLE, [
                named_table, protected, ordered_set
            ]),
            ok;
        _ ->
            ok
    end.

%% @doc Create the sorting ETS table if it doesn't exist
%%
%% Creates a table for fast story ID to ranking order lookups.
%% This enables efficient story retrieval by ID without scanning
%% the entire stories table.
%%
%% Table structure: {StoryId, Order}
%% - StoryId: Hacker News story ID from the API
%% - Order: Corresponding ranking position in stories table
%%
%% @returns ok
%% @end
-spec create_sorting_table() -> ok.
create_sorting_table() ->
    case ets:info(?SORTING_TABLE) of
        undefined ->
            ?SORTING_TABLE = ets:new(?SORTING_TABLE, [
                named_table, protected
            ]),
            ok;
        _ ->
            ok
    end.
