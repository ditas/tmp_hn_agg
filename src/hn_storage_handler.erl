-module(hn_storage_handler).

-behaviour(gen_server).

-include("common.hrl").

-export([start_link/0]).

-export([store_story/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% API
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Using this function from any caller avoids bottlenecking on ETS communication from multiple processes
%% Having it as a gen_server allows further improvements like batching writes
%% or adding more complex logic if needed
store_story(Order, Story) ->
    true = ets:insert(?DEFAULT_STORIES_TABLE, {Order, Story}),
    ok.

init([]) ->
    case ets:info(?DEFAULT_STORIES_TABLE) of
        undefined ->
            ?DEFAULT_STORIES_TABLE = ets:new(?DEFAULT_STORIES_TABLE, [
                named_table, public, ordered_set
            ]);
        _Info ->
            ignore
    end,
    {ok, #{}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
