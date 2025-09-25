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

%% Callbacks/API

-spec init(cowboy_req:req(), any()) -> {cowboy_rest, cowboy_req:req(), map()}.
init(Req, []) ->
    {ok, PageSize} = application:get_env(hn_aggregator, page_size),
    {ok, MaxRequestsPerMinute} = application:get_env(hn_aggregator, max_requests_per_minute),
    {cowboy_rest, Req, #{
        page_size => PageSize,
        max_requests_per_minute => MaxRequestsPerMinute
    }}.

-spec allowed_methods(cowboy_req:req(), map()) -> {[binary()], cowboy_req:req(), map()}.
allowed_methods(Req, State) ->
    {[<<"GET">>], Req, State}.

-spec content_types_provided(cowboy_req:req(), map()) ->
    {[{{binary(), binary(), '*'}, atom()}], cowboy_req:req(), map()}.
content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}], Req, State}.

-spec is_authorized(cowboy_req:req(), map()) -> {boolean(), cowboy_req:req(), map()}.
is_authorized(Req, State) ->
    {true, Req, State}.

-spec rate_limited(cowboy_req:req(), map()) -> {boolean(), cowboy_req:req(), map()}.
rate_limited(Req, #{max_requests_per_minute := MaxRequestsPerMinute} = State) ->
    {IP, Port} = cowboy_req:peer(Req),
    ?LOG_DEBUG("Peer IP: ~p, Port: ~p", [IP, Port]),
    Res =
        case hn_rate_limiter:check_rate_limit(IP, MaxRequestsPerMinute) of
            allow ->
                false;
            {disallow, RetryAfter} ->
                {true, RetryAfter}
        end,
    {Res, Req, State}.

-spec to_json(cowboy_req:req(), map()) -> {atom(), cowboy_req:req(), map()}.
to_json(Req, State) ->
    Req1 = handle_request(Req, State),
    {stop, Req1, State}.

%% Internal

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
