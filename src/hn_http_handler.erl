%% @doc HTTP REST Handler for Hacker News Stories API
%%
%% This module implements a Cowboy REST handler that provides HTTP endpoints
%% for accessing stored Hacker News stories. It supports both paginated story
%% listings and individual story retrieval by ID.
%%
%% The handler implements rate limiting per client IP address and provides
%% JSON responses for all endpoints. It integrates with the storage handler
%% for data retrieval and the rate limiter for access control.
%%
%% Supported endpoints:
%% - GET /stories?page=N - Paginated list of top stories
%% - GET /stories/:id - Individual story by Hacker News ID
%%
%% Features:
%% - IP-based rate limiting with configurable thresholds
%% - Paginated responses for efficient data transfer
%% - RESTful HTTP status codes and error handling
%%
%% Configuration:
%% - `page_size': Number of stories per page for pagination
%% - `max_http_requests': Maximum HTTP requests per IP per time window
%%
%% @end
-module(hn_http_handler).

-behaviour(cowboy_rest).

-include_lib("kernel/include/logger.hrl").

-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    is_authorized/2,
    rate_limited/2
]).

-export([to_json/2]).

-type state() :: #{
    page_size := pos_integer(),
    max_requests := pos_integer()
}.

%% Callbacks/API

-spec init(cowboy_req:req(), any()) -> {cowboy_rest, cowboy_req:req(), state()}.
init(Req, []) ->
    {ok, PageSize} = application:get_env(hn_aggregator, page_size),
    {ok, MaxRequests} = application:get_env(hn_aggregator, max_http_requests),
    {cowboy_rest, Req, #{
        page_size => PageSize,
        max_requests => MaxRequests
    }}.

-spec allowed_methods(cowboy_req:req(), state()) -> {[binary()], cowboy_req:req(), state()}.
allowed_methods(Req, State) ->
    {[<<"GET">>], Req, State}.

-spec content_types_provided(cowboy_req:req(), state()) ->
    {[{{binary(), binary(), '*'}, atom()}], cowboy_req:req(), state()}.
content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}], Req, State}.

-spec is_authorized(cowboy_req:req(), state()) -> {boolean(), cowboy_req:req(), state()}.
is_authorized(Req, State) ->
    {true, Req, State}.

-spec rate_limited(cowboy_req:req(), state()) -> {boolean(), cowboy_req:req(), state()}.
rate_limited(Req, #{max_requests := MaxRequests} = State) ->
    {IP, Port} = cowboy_req:peer(Req),
    ?LOG_DEBUG("Peer IP: ~p, Port: ~p", [IP, Port]),
    Res =
        case hn_rate_limiter:check_connection_rate_limit(IP, MaxRequests) of
            allow ->
                false;
            {disallow, RetryAfter} ->
                {true, RetryAfter}
        end,
    {Res, Req, State}.

-spec to_json(cowboy_req:req(), state()) -> {atom(), cowboy_req:req(), state()}.
to_json(Req, State) ->
    Req1 = handle_request(Req, State),
    {stop, Req1, State}.

%% Internal

%% @doc Handle the actual HTTP request logic
%%
%% Processes two types of requests:
%% 1. Story listings: GET /stories?page=N
%%    - Extracts page parameter (defaults to 1)
%%    - Retrieves paginated stories from storage
%%    - Returns JSON array of stories
%%
%% 2. Individual stories: GET /stories/:id
%%    - Extracts story ID from URL path
%%    - Looks up story by ID in storage
%%    - Returns single story JSON or 404 if not found
%%
%% @returns Updated request object with response sent
%% @end
-spec handle_request(cowboy_req:req(), map()) -> cowboy_req:req().
handle_request(Req, #{page_size := PageSize}) ->
    case cowboy_req:binding(id, Req) of
        undefined ->
            ?LOG_DEBUG("Request received for stories"),
            Page = cowboy_req:parse_qs(Req),
            PageNum = binary_to_integer(proplists:get_value(<<"page">>, Page, <<"1">>)),
            {ok, Stories} = hn_storage_handler:read_stories(PageNum, PageSize),
            Body = jsone:encode(Stories),
            cowboy_req:reply(200, #{}, Body, Req);
        Id ->
            ?LOG_DEBUG("Request received for story ID: ~p", [Id]),
            case hn_storage_handler:read_story_by_id(binary_to_integer(Id)) of
                {ok, Story} ->
                    ?LOG_DEBUG("Story found: ~p", [Story]),
                    Body = jsone:encode(Story),
                    cowboy_req:reply(200, #{}, Body, Req);
                {error, not_found} ->
                    cowboy_req:reply(404, #{}, <<"Story not found">>, Req)
            end
    end.
