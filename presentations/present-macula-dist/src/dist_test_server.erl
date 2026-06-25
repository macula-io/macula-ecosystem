%%%-------------------------------------------------------------------
%%% @doc Automated dist-over-mesh test server.
%%%
%%% Connects to a relay, registers on the mesh, then periodically
%%% pings peer nodes and tests Erlang distribution primitives.
%%%
%%% Environment variables:
%%%   MACULA_RELAY           — station URL for pub/sub (mesh_chat): https://relay-it-milan.macula.io:4433
%%%   MACULA_DIST_RELAY_URL  — explicit dist relay URL (quic://...:4434). Overrides
%%%                            the auto-derived geo URL. Use when pointing at a
%%%                            specific box or a non-standard identity.
%%%   MACULA_GEO_COUNTRY     — ISO 3166-1 alpha-2 (e.g., "BE", "IT"). Combined with
%%%                            MACULA_GEO_CITY, the dist-relay URL is auto-derived as
%%%                            quic://dist-{cc-lower}-{city-slug}.macula.io:4434 —
%%%                            matching the dist-{cc}-{city} virtual identity naming
%%%                            on the dist-relay fleet.
%%%   MACULA_GEO_CITY        — City name (e.g., "Brussels", "Banja Luka"). Slugged.
%%%   PING_TARGETS           — comma-separated peer node names
%%%   PING_INTERVAL_MS       — ping interval in ms (default: 15000)
%%%
%%% Results logged to stdout. Process stays alive — run as a Docker
%%% container for continuous automated testing.
%%% @end
%%%-------------------------------------------------------------------
-module(dist_test_server).
-behaviour(gen_server).

-export([start_link/0]).
-export([derive_dist_relay_url/0]).  %% Exported for tests + diagnostic shell use
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DEFAULT_INTERVAL, 15000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Interval = env_int("PING_INTERVAL_MS", ?DEFAULT_INTERVAL),
    Targets = parse_targets(os:getenv("PING_TARGETS", "")),
    RelayUrl = env_bin("MACULA_RELAY"),
    DistRelayUrl = derive_dist_relay_url(),

    log("Starting dist_test_server on ~s", [node()]),
    log("Station relay: ~s", [RelayUrl]),
    log("Dist relay:    ~s", [DistRelayUrl]),
    log("Targets:       ~p", [Targets]),

    ensure_pg(),
    maybe_join_mesh(RelayUrl),
    %% If a dedicated dist relay is configured, use it for dist traffic.
    %% This sets MACULA_DIST_MODE=dist_relay, overriding the pub/sub
    %% bridge that join_mesh/1 defaults to.
    maybe_join_dist_relay(DistRelayUrl),

    %% Only start auto-ping loop when targets are configured (Docker mode).
    %% Interactive shell sessions use mesh_chat commands instead.
    case Targets of
        [] -> ok;
        _  -> erlang:send_after(10000, self(), ping_peers)
    end,

    {ok, #{
        targets => Targets,
        interval => Interval,
        started => erlang:system_time(second),
        stats => #{pings => 0, pongs => 0, pangs => 0,
                   rpc_ok => 0, rpc_fail => 0,
                   gs_ok => 0, gs_fail => 0}
    }}.

handle_call(ping, _From, State) ->
    {reply, {pong, node()}, State};

handle_call(get_state, _From, State) ->
    {reply, {ok, State#{node => node(), connected => nodes()}}, State};

handle_call(stats, _From, #{stats := Stats} = State) ->
    {reply, Stats, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(ping_peers, #{targets := Targets, interval := Interval,
                           stats := Stats} = State) ->
    Stats2 = lists:foldl(fun(Target, Acc) ->
        test_peer(Target, Acc)
    end, Stats, Targets),

    %% Log summary every cycle
    Connected = nodes(),
    log("Peers: ~b connected, stats: ~p", [length(Connected), Stats2]),

    erlang:send_after(Interval, self(), ping_peers),
    {noreply, State#{stats := Stats2}};

handle_info(_Msg, State) ->
    {noreply, State}.

%%====================================================================
%% Test functions
%%====================================================================

test_peer(Target, Stats) ->
    #{pings := Pings, pongs := Pongs, pangs := Pangs,
      rpc_ok := RpcOk, rpc_fail := RpcFail,
      gs_ok := GsOk, gs_fail := GsFail} = Stats,

    %% Test 1: net_adm:ping
    PingResult = net_adm:ping(Target),
    {Pongs2, Pangs2} = ping_tally(PingResult, Target, Pongs, Pangs),

    %% Test 2+3: only if ping succeeded
    {RpcOk2, RpcFail2, GsOk2, GsFail2} =
        rpc_gs_tally(PingResult, Target, RpcOk, RpcFail, GsOk, GsFail),

    #{pings => Pings + 1, pongs => Pongs2, pangs => Pangs2,
      rpc_ok => RpcOk2, rpc_fail => RpcFail2,
      gs_ok => GsOk2, gs_fail => GsFail2}.

ping_tally(pong, Target, Pongs, Pangs) ->
    log("PING ~s → \e[32mpong\e[0m", [Target]),
    {Pongs + 1, Pangs};
ping_tally(pang, Target, Pongs, Pangs) ->
    log("PING ~s → \e[31mpang\e[0m", [Target]),
    {Pongs, Pangs + 1}.

rpc_gs_tally(pong, Target, RpcOk, RpcFail, GsOk, GsFail) ->
    RpcRes = rpc_test(Target),
    GsRes = gs_test(Target),
    {RpcOk + ok_count(RpcRes), RpcFail + fail_count(RpcRes),
     GsOk + ok_count(GsRes), GsFail + fail_count(GsRes)};
rpc_gs_tally(pang, _Target, RpcOk, RpcFail, GsOk, GsFail) ->
    {RpcOk, RpcFail, GsOk, GsFail}.

%% Test 2: rpc:call
rpc_test(Target) ->
    rpc_result(rpc:call(Target, erlang, node, []), Target).

rpc_result(Target, Target) ->
    log("RPC  ~s → \e[32mok\e[0m (node=~s)", [Target, Target]),
    ok;
rpc_result({badrpc, Reason}, Target) ->
    log("RPC  ~s → \e[31mfail\e[0m (~p)", [Target, Reason]),
    fail;
rpc_result(Other, Target) ->
    log("RPC  ~s → \e[31mfail\e[0m (got ~p)", [Target, Other]),
    fail.

%% Test 3: gen_server:call
gs_test(Target) ->
    gs_result(catch gen_server:call({dist_test_server, Target}, ping, 5000), Target).

gs_result({pong, Target}, Target) ->
    log("GS   ~s → \e[32mpong\e[0m", [Target]),
    ok;
gs_result(GsErr, Target) ->
    log("GS   ~s → \e[31mfail\e[0m (~p)", [Target, GsErr]),
    fail.

ok_count(ok) -> 1;
ok_count(_) -> 0.

fail_count(fail) -> 1;
fail_count(_) -> 0.

%%====================================================================
%% Helpers
%%====================================================================

parse_targets("") -> [];
parse_targets(Env) ->
    [list_to_atom(string:trim(T))
     || T <- string:split(Env, ",", all),
        string:trim(T) =/= ""].

env_int(Key, Default) ->
    env_int_value(os:getenv(Key), Default).

env_int_value(false, Default) -> Default;
env_int_value("", Default) -> Default;
env_int_value(Val, Default) ->
    try list_to_integer(Val)
    catch _:_ -> Default
    end.

env_bin(Key) ->
    case os:getenv(Key) of
        false -> undefined;
        "" -> undefined;
        Val -> list_to_binary(Val)
    end.

%% Explicit MACULA_DIST_RELAY_URL wins; otherwise derive from geo vars
%% (MACULA_GEO_COUNTRY + MACULA_GEO_CITY) to match the dist-{cc}-{city}
%% virtual identity naming. Returns undefined when nothing is configured,
%% which keeps dist on the legacy pub/sub bridge.
derive_dist_relay_url() ->
    pick_dist_url(env_bin("MACULA_DIST_RELAY_URL"),
                  env_bin("MACULA_GEO_COUNTRY"),
                  env_bin("MACULA_GEO_CITY")).

pick_dist_url(Explicit, _CC, _City) when Explicit =/= undefined ->
    Explicit;
pick_dist_url(_Explicit, undefined, _City) ->
    undefined;
pick_dist_url(_Explicit, _CC, undefined) ->
    undefined;
pick_dist_url(_Explicit, CC, City) ->
    CcLower = string:lowercase(CC),
    CitySlug = slug(City),
    iolist_to_binary(["quic://dist-", CcLower, "-", CitySlug, ".macula.io:4434"]).

%% Kebab-case a city name: lowercase + collapse whitespace to single hyphens.
%% Matches the convention in relay-identities.txt / dist-identities.txt
%% (e.g., "Banja Luka" → "banja-luka").
slug(Bin) when is_binary(Bin) ->
    Lower = string:lowercase(Bin),
    re:replace(Lower, <<"\\s+">>, <<"-">>, [global, {return, binary}]).

ensure_pg() ->
    case pg:start(pg) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end.

maybe_join_mesh(undefined) ->
    log("WARNING: No MACULA_RELAY set — running without mesh", []);
maybe_join_mesh(Url) ->
    case macula:join_mesh(#{relays => [Url], realm => <<"io.macula">>}) of
        ok -> log("Mesh joined via ~s", [Url]);
        {error, Reason} -> log("ERROR: join_mesh failed: ~p", [Reason])
    end.

maybe_join_dist_relay(undefined) ->
    log("No MACULA_DIST_RELAY_URL — dist will use pub/sub bridge (legacy)", []);
maybe_join_dist_relay(Url) ->
    case macula:join_dist_relay(#{url => Url}) of
        ok -> log("Dist relay joined via ~s — dist_mode=dist_relay", [Url]);
        {error, Reason} -> log("ERROR: join_dist_relay failed: ~p", [Reason])
    end.

log(Fmt, Args) ->
    Ts = calendar:system_time_to_rfc3339(erlang:system_time(second)),
    io:format("[dist_test ~s] " ++ Fmt ++ "~n", [Ts | Args]).
