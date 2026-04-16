%%%-------------------------------------------------------------------
%%% @doc Tests for dist_test_server URL derivation.
%%%
%%% Verifies dist_test_server:derive_dist_relay_url/0 composes the
%%% dist-{cc}-{city}.macula.io URL from MACULA_GEO_COUNTRY +
%%% MACULA_GEO_CITY env vars, with MACULA_DIST_RELAY_URL as an
%%% explicit override and undefined fallback.
%%% @end
%%%-------------------------------------------------------------------
-module(dist_test_server_tests).

-include_lib("eunit/include/eunit.hrl").

explicit_url_wins_test() ->
    with_env(
        [{"MACULA_DIST_RELAY_URL", "quic://custom.example:9999"},
         {"MACULA_GEO_COUNTRY", "BE"},
         {"MACULA_GEO_CITY", "Brussels"}],
        fun() ->
            ?assertEqual(<<"quic://custom.example:9999">>,
                         dist_test_server:derive_dist_relay_url())
        end).

derives_from_country_and_city_test() ->
    with_env(
        [{"MACULA_DIST_RELAY_URL", ""},
         {"MACULA_GEO_COUNTRY", "BE"},
         {"MACULA_GEO_CITY", "Brussels"}],
        fun() ->
            ?assertEqual(<<"quic://dist-be-brussels.macula.io:4434">>,
                         dist_test_server:derive_dist_relay_url())
        end).

slugs_multi_word_city_test() ->
    with_env(
        [{"MACULA_DIST_RELAY_URL", ""},
         {"MACULA_GEO_COUNTRY", "BA"},
         {"MACULA_GEO_CITY", "Banja Luka"}],
        fun() ->
            ?assertEqual(<<"quic://dist-ba-banja-luka.macula.io:4434">>,
                         dist_test_server:derive_dist_relay_url())
        end).

undefined_when_no_geo_test() ->
    with_env(
        [{"MACULA_DIST_RELAY_URL", ""},
         {"MACULA_GEO_COUNTRY", ""},
         {"MACULA_GEO_CITY", ""}],
        fun() ->
            ?assertEqual(undefined, dist_test_server:derive_dist_relay_url())
        end).

undefined_when_only_country_test() ->
    with_env(
        [{"MACULA_DIST_RELAY_URL", ""},
         {"MACULA_GEO_COUNTRY", "IT"},
         {"MACULA_GEO_CITY", ""}],
        fun() ->
            ?assertEqual(undefined, dist_test_server:derive_dist_relay_url())
        end).

country_lowercased_test() ->
    with_env(
        [{"MACULA_DIST_RELAY_URL", ""},
         {"MACULA_GEO_COUNTRY", "SE"},
         {"MACULA_GEO_CITY", "Stockholm"}],
        fun() ->
            ?assertEqual(<<"quic://dist-se-stockholm.macula.io:4434">>,
                         dist_test_server:derive_dist_relay_url())
        end).

%%====================================================================
%% Helpers
%%====================================================================

with_env(Pairs, Fun) ->
    Saved = [{K, os:getenv(K)} || {K, _} <- Pairs],
    try
        [os:putenv(K, V) || {K, V} <- Pairs],
        Fun()
    after
        [restore(K, V) || {K, V} <- Saved]
    end.

restore(K, false) -> os:unsetenv(K);
restore(K, V) -> os:putenv(K, V).
