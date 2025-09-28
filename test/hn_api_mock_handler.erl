-module(hn_api_mock_handler).

-include("test/include/test_shared.hrl").

-export([init/2]).

init(Req, State) ->
    _ = handle(cowboy_req:method(Req), cowboy_req:path(Req), Req),
    {ok, Req, State}.

handle(<<"GET">>, <<"/v0/topstories.json">>, Req) ->
    ct:pal("=======================TOP=======================GET ~p", [Req]),
    Data = jsone:encode(?STORIES_IDS),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Data, Req);
handle(<<"GET">>, _, Req) ->
    Item = cowboy_req:binding(item, Req),
    [Id|_] = binary:split(Item, <<".">>),
    ct:pal("=======================ITEM=======================GET ~p", [Item]),
    [Story] = lists:filter(fun(#{<<"id">> := Id0}) ->
        binary_to_integer(Id) =:= Id0
    end, ?STORIES),
    Data = jsone:encode(Story),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Data, Req).
