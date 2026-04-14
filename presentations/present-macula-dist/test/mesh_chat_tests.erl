-module(mesh_chat_tests).
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% URL normalization
%%====================================================================

normalize_bare_name_test() ->
    ?assertEqual(<<"https://relay-de-berlin.macula.io:4433">>,
                 mesh_chat:normalize_relay_url(<<"relay-de-berlin">>)).

%% Short form — `it-palermo' → relay-it-palermo.macula.io:4433
normalize_short_form_test() ->
    ?assertEqual(<<"https://relay-it-palermo.macula.io:4433">>,
                 mesh_chat:normalize_relay_url(<<"it-palermo">>)).

%% Already-prefixed short form — no double prefix
normalize_short_already_prefixed_test() ->
    ?assertEqual(<<"https://relay-de-berlin.macula.io:4433">>,
                 mesh_chat:normalize_relay_url(<<"relay-de-berlin">>)).

%% FQDN without relay- prefix — user was explicit, don't meddle
normalize_fqdn_no_relay_test() ->
    ?assertEqual(<<"https://my-box.example.com:4433">>,
                 mesh_chat:normalize_relay_url(<<"my-box.example.com">>)).

normalize_fqdn_test() ->
    ?assertEqual(<<"https://relay-de-berlin.macula.io:4433">>,
                 mesh_chat:normalize_relay_url(<<"relay-de-berlin.macula.io">>)).

normalize_with_port_test() ->
    ?assertEqual(<<"https://relay-de-berlin.macula.io:9443">>,
                 mesh_chat:normalize_relay_url(<<"relay-de-berlin.macula.io:9443">>)).

normalize_already_https_test() ->
    ?assertEqual(<<"https://relay-de-berlin.macula.io:4433">>,
                 mesh_chat:normalize_relay_url(<<"https://relay-de-berlin.macula.io:4433">>)).

normalize_http_passthrough_test() ->
    ?assertEqual(<<"http://localhost:4433">>,
                 mesh_chat:normalize_relay_url(<<"http://localhost:4433">>)).

%%====================================================================
%% URL stripping
%%====================================================================

strip_url_https_test() ->
    ?assertEqual("relay-de-berlin.macula.io",
                 mesh_chat:strip_url(<<"https://relay-de-berlin.macula.io:4433">>)).

strip_url_http_test() ->
    ?assertEqual("localhost",
                 mesh_chat:strip_url(<<"http://localhost:4433">>)).

strip_url_no_scheme_test() ->
    ?assertEqual("relay-de-berlin.macula.io",
                 mesh_chat:strip_url(<<"relay-de-berlin.macula.io:4433">>)).

strip_url_non_binary_test() ->
    ?assertEqual("unknown", mesh_chat:strip_url(undefined)).

%%====================================================================
%% Short node name
%%====================================================================

short_node_with_host_test() ->
    ?assertEqual("alice", mesh_chat:short_node('alice@host00.lab')).

short_node_bare_test() ->
    ?assertEqual("nohost", mesh_chat:short_node(nohost)).

%%====================================================================
%% Room key
%%====================================================================

room_key_test() ->
    ?assertEqual({mesh_chat_room, "lobby"}, mesh_chat:room_key("lobby")).

%%====================================================================
%% Plural
%%====================================================================

plural_one_test() ->
    ?assertEqual("", mesh_chat:plural(1)).

plural_many_test() ->
    ?assertEqual("s", mesh_chat:plural(0)),
    ?assertEqual("s", mesh_chat:plural(5)).

%%====================================================================
%% Presence — peer filtering
%%====================================================================

maybe_connect_self_test() ->
    %% Connecting to self is a no-op (returns ok, no spawn)
    ?assertEqual(ok, mesh_chat:maybe_connect_peer(node())).

%%====================================================================
%% extract_city
%%====================================================================

extract_city_full_url_test() ->
    ?assertEqual("palermo",
                 mesh_chat:extract_city(<<"https://relay-it-palermo.macula.io:4433">>)).

extract_city_bare_hostname_test() ->
    ?assertEqual("lisbon",
                 mesh_chat:extract_city(<<"relay-pt-lisbon.macula.io">>)).

extract_city_undefined_test() ->
    ?assertEqual("—", mesh_chat:extract_city(undefined)).

extract_city_non_standard_test() ->
    %% Fallback to the stripped host when the slug isn't `relay-xx-city'.
    ?assertEqual("box.example.com",
                 mesh_chat:extract_city(<<"https://box.example.com:4433">>)).

%%====================================================================
%% URL helpers
%%====================================================================

maybe_append_domain_bare_test() ->
    ?assertEqual(<<"relay-de-berlin.macula.io">>,
                 mesh_chat:maybe_append_domain(<<"relay-de-berlin">>)).

maybe_append_domain_fqdn_test() ->
    ?assertEqual(<<"relay-de-berlin.macula.io">>,
                 mesh_chat:maybe_append_domain(<<"relay-de-berlin.macula.io">>)).

maybe_append_port_without_test() ->
    ?assertEqual(<<"https://relay-de-berlin.macula.io:4433">>,
                 mesh_chat:maybe_append_port(<<"relay-de-berlin.macula.io">>, <<"4433">>)).

maybe_append_port_with_test() ->
    ?assertEqual(<<"https://relay-de-berlin.macula.io:9443">>,
                 mesh_chat:maybe_append_port(<<"relay-de-berlin.macula.io:9443">>, <<"4433">>)).
