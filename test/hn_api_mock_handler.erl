-module(hn_api_mock_handler).

-export([init/2]).

-define(STORIES_IDS, [123, 456, 789, 101112, 131415, 161718, 192021]).
-define(STORIES, [
    #{
        <<"by">> => <<"test1">>,
        <<"descendants">> => 1,
        <<"id">> => 123,
        <<"kids">> => [],
        <<"score">> => 155,
        <<"time">> => 1758828112,
        <<"title">> => <<"Test1 Title">>,
        <<"type">> => <<"story">>,
        <<"url">> => <<"https://test1.com">>
    },
    #{
        <<"by">> => <<"test2">>,
        <<"descendants">> => 1,
        <<"id">> => 456,
        <<"kids">> => [],
        <<"score">> => 333,
        <<"time">> => 1758828112,
        <<"title">> => <<"Test2 Title">>,
        <<"type">> => <<"story">>,
        <<"url">> => <<"https://test2.com">>
    },
    #{
        <<"by">> => <<"test3">>,
        <<"descendants">> => 1,
        <<"id">> => 789,
        <<"kids">> => [],
        <<"score">> => 231,
        <<"time">> => 1758828112,
        <<"title">> => <<"Test3 Title">>,
        <<"type">> => <<"story">>,
        <<"url">> => <<"https://test3.com">>
    },
    #{
        <<"by">> => <<"test4">>,
        <<"descendants">> => 1,
        <<"id">> => 101112,
        <<"kids">> => [],
        <<"score">> => 332,
        <<"time">> => 1758828112,
        <<"title">> => <<"Test4 Title">>,
        <<"type">> => <<"story">>,
        <<"url">> => <<"https://test4.com">>
    },
    #{
        <<"by">> => <<"test5">>,
        <<"descendants">> => 1,
        <<"id">> => 131415,
        <<"kids">> => [],
        <<"score">> => 654,
        <<"time">> => 1758828112,
        <<"title">> => <<"Test5 Title">>,
        <<"type">> => <<"story">>,
        <<"url">> => <<"https://test5.com">>
    }
]).

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
