-module(hn_api_mock_handler).

-export([init/2]).

-define(STORIES_IDS, [123, 456, 789, 101112, 131415, 161718, 192021]).

init(Req, MockStateTable) ->
    handle(cowboy_req:method(Req), Req, MockStateTable).

handle(<<"GET">>, Req, MockStateTable) ->
    ct:pal("==============================================GET ~p", [Req]),
    % case cowboy_req:binding(top, Req) of
    %     undefined ->
    %         handle_get(cowboy_req:path(Req), Req, MockStateTable);
    %     Filename ->
    %         handle_get(Filename, Req, MockStateTable)
    % end.
    handle_get(cowboy_req:path(Req), Req, MockStateTable).

handle_get(<<"/v0/topstories.json">>, Req, MockStateTable) ->
    ct:pal("==============================================Mocking topstories.json"),
    % [TopStoriesIds] = ets:lookup(MockStateTable, topstories),
    % Data = jsone:encode(TopStoriesIds),
    Data = jsone:encode(?STORIES_IDS),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Data, Req);
handle_get(Filename, Req, MockStateTable) ->
    ct:pal("==============================================Mocking ~s", [Filename]),
    [Id|_] = binary:split(Filename, <<".">>),
    [Story] = ets:lookup(MockStateTable, Id),
    Data = jsone:encode(Story),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Data, Req).
