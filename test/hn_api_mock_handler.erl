-module(hn_api_mock_handler).

-include("test/include/test_shared.hrl").

-export([init/2]).

init(Req, []) ->
    _ = handle(cowboy_req:method(Req), cowboy_req:path(Req), Req),
    {ok, Req, #{}}.

handle(<<"GET">>, <<"/v0/topstories.json">>, Req) ->
    %% Mocking HN API response delay
    RespDelay = case application:get_env(hn_aggregator, ?HN_API_MOCK_DELAY_KEY) of
        undefined -> 0;
        {ok, Delay} -> Delay
    end,
    ct:pal("=======================TOP=======================RespDelay ~p", [RespDelay]),

    ct:pal("=======================TOP=======================GET ~p", [Req]),
    timer:sleep(RespDelay),
    Data = jsone:encode(?STORIES_IDS),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Data, Req);
handle(<<"GET">>, _, Req) ->
    %% Mocking HN API story not found
    NotFoundId = case application:get_env(hn_aggregator, ?HN_API_MOCK_NOT_FOUND_STORY_ID_KEY) of
        undefined -> undefined;
        {ok, StoryId} -> StoryId
    end,
    ct:pal("=======================ITEM=======================NotFoundId ~p", [NotFoundId]),

    Item = cowboy_req:binding(item, Req),
    [IdBin|_] = binary:split(Item, <<".">>),
    Id = binary_to_integer(IdBin),
    ct:pal("=======================ITEM=======================GET ~p", [Item]),
    case Id =:= NotFoundId of
      true ->
          cowboy_req:reply(404, #{}, <<"Story not found">>, Req);
      false ->
          [Story] = lists:filter(fun(#{<<"id">> := Id0}) ->
              Id =:= Id0
          end, ?STORIES),
          Data = jsone:encode(Story),
          cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Data, Req)
    end.
