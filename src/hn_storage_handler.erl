-module(hn_storage_handler).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").

-export([start_link/0]).

-export([store_stories/1]).
-export([read_stories/2, read_story_by_id/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(DEFAULT_STORIES_TABLE, stories).
-define(DEFAULT_SORTING_TABLE, sorting).

%% API
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

store_stories(Stories) ->
    gen_server:cast(?MODULE, {store_stories, Stories}).

read_stories(PageNum, PageSize) ->
    Offset = (PageNum - 1) * PageSize,
    Range = Offset + PageSize,
    Stories = ets:select(?DEFAULT_STORIES_TABLE, [
        {{'$1', '$2'}, [{'>', '$1', Offset}, {'=<', '$1', Range}], [{{'$1', '$2'}}]}
    ]),
    [Story || {_, Story} <- Stories].

read_story_by_id(Id) ->
    case ets:lookup(?DEFAULT_SORTING_TABLE, Id) of
        [] ->
            {error, not_found};
        [{_, Order}] ->
            case ets:lookup(?DEFAULT_STORIES_TABLE, Order) of
                [] -> {error, not_found};
                [{_, Story}] -> {ok, Story}
            end
    end.

init([]) ->
    ok = create_story_table(),
    ok = create_sorting_table(),
    {ok, #{}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({store_stories, Stories}, State) ->
    ?LOG_DEBUG("Storing stories: ~p", [Stories]),
    true = ets:insert(?DEFAULT_STORIES_TABLE, Stories),
    IdsOrders = lists:foldl(
        fun({Order, #{<<"id">> := Id}}, Acc) ->
            [{Id, Order} | Acc]
        end,
        [],
        Stories
    ),
    ?LOG_DEBUG("Storing id-to-order mappings: ~p", [IdsOrders]),
    true = ets:insert(?DEFAULT_SORTING_TABLE, IdsOrders),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal

create_story_table() ->
    case ets:info(?DEFAULT_STORIES_TABLE) of
        undefined ->
            ?DEFAULT_STORIES_TABLE = ets:new(?DEFAULT_STORIES_TABLE, [
                named_table, protected, ordered_set
            ]),
            ok;
        _ ->
            ok
    end.

create_sorting_table() ->
    case ets:info(?DEFAULT_SORTING_TABLE) of
        undefined ->
            ?DEFAULT_SORTING_TABLE = ets:new(?DEFAULT_SORTING_TABLE, [
                named_table, protected
            ]),
            ok;
        _ ->
            ok
    end.
