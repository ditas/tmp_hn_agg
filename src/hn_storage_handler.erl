-module(hn_storage_handler).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").

-export([start_link/0]).

-export([store_stories/1]).
-export([read_stories/2, read_story_by_id/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(STORIES_TABLE, stories).
-define(SORTING_TABLE, sorting).

-type state() :: map().

%% API
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec store_stories(list()) -> ok.
store_stories(Stories) ->
    gen_server:cast(?MODULE, {store_stories, Stories}).

-spec read_stories(non_neg_integer(), pos_integer()) -> {ok, list()}.
read_stories(PageNum, PageSize) ->
    Offset = (PageNum - 1) * PageSize,
    Range = Offset + PageSize,
    Stories = ets:select(?STORIES_TABLE, [
        {{'$1', '$2'}, [{'>', '$1', Offset}, {'=<', '$1', Range}], [{{'$1', '$2'}}]}
    ]),
    {ok, [Story || {_, Story} <- Stories]}.

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
