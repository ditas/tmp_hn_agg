-define(STORIES_IDS, [123, 456, 789, 101112, 131415, 161718, 192021]). %% 7 stories ids
%% 5 stories to fetch
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

-define(STORY_456, #{
        <<"by">> => <<"test2">>,
        <<"descendants">> => 1,
        <<"id">> => 456,
        <<"kids">> => [],
        <<"score">> => 333,
        <<"time">> => 1758828112,
        <<"title">> => <<"Test2 Title">>,
        <<"type">> => <<"story">>,
        <<"url">> => <<"https://test2.com">>
    }).

-define(STORY_131415, #{
        <<"by">> => <<"test5">>,
        <<"descendants">> => 1,
        <<"id">> => 131415,
        <<"kids">> => [],
        <<"score">> => 654,
        <<"time">> => 1758828112,
        <<"title">> => <<"Test5 Title">>,
        <<"type">> => <<"story">>,
        <<"url">> => <<"https://test5.com">>
    }).

-define(HN_API_MOCK_DELAY_KEY, hn_api_mock_delay).
-define(HN_API_MOCK_NOT_FOUND_STORY_ID_KEY, hn_api_mock_not_found_story_id).
