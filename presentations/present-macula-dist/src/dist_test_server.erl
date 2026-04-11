%%%-------------------------------------------------------------------
%%% @doc Automated dist-over-mesh test server.
%%%
%%% Connects to a relay, registers on the mesh, then periodically
%%% pings peer nodes and tests Erlang distribution primitives.
%%%
%%% Environment variables:
%%%   MACULA_RELAY     — relay URL (e.g., https://relay-it-milan.macula.io:4433)
%%%   PING_TARGETS     — comma-separated peer node names (e.g., alice@nanode-milan)
%%%   PING_INTERVAL_MS — ping interval in ms (default: 15000)
%%%
%%% Results logged to stdout. Process stays alive — run as a Docker
%%% container for continuous automated testing.
%%% @end
%%%-------------------------------------------------------------------
-module(dist_test_server).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DEFAULT_INTERVAL, 15000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Interval = env_int("PING_INTERVAL_MS", ?DEFAULT_INTERVAL),
    Targets = parse_targets(os:getenv("PING_TARGETS", "")),
    RelayUrl = case os:getenv("MACULA_RELAY") of
        false -> undefined;
        "" -> undefined;
        Url -> list_to_binary(Url)
    end,

    log("Starting dist_test_server on ~s", [node()]),
    log("Relay:   ~s", [RelayUrl]),
    log("Targets: ~p", [Targets]),

    %% Connect to mesh
    case RelayUrl of
        undefined ->
            log("WARNING: No MACULA_RELAY set — running without mesh", []);
        _ ->
            case pg:start(pg) of
                {ok, _} -> ok;
                {error, {already_started, _}} -> ok
            end,
            case macula:join_mesh(#{relays => [RelayUrl], realm => <<"io.macula">>}) of
                ok -> log("Mesh joined via ~s", [RelayUrl]);
                {error, Reason} -> log("ERROR: join_mesh failed: ~p", [Reason])
            end
    end,

    %% Start pinging after 10s (let mesh stabilize)
    erlang:send_after(10000, self(), ping_peers),

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
    {Pongs2, Pangs2} = case PingResult of
        pong ->
            log("PING ~s → \e[32mpong\e[0m", [Target]),
            {Pongs + 1, Pangs};
        pang ->
            log("PING ~s → \e[31mpang\e[0m", [Target]),
            {Pongs, Pangs + 1}
    end,

    %% Test 2+3: only if ping succeeded
    {RpcOk2, RpcFail2, GsOk2, GsFail2} = case PingResult of
        pong ->
            %% Test 2: rpc:call
            RpcRes = case rpc:call(Target, erlang, node, []) of
                Target ->
                    log("RPC  ~s → \e[32mok\e[0m (node=~s)", [Target, Target]),
                    ok;
                {badrpc, Reason} ->
                    log("RPC  ~s → \e[31mfail\e[0m (~p)", [Target, Reason]),
                    fail;
                Other ->
                    log("RPC  ~s → \e[31mfail\e[0m (got ~p)", [Target, Other]),
                    fail
            end,

            %% Test 3: gen_server:call
            GsRes = case catch gen_server:call({dist_test_server, Target}, ping, 5000) of
                {pong, Target} ->
                    log("GS   ~s → \e[32mpong\e[0m", [Target]),
                    ok;
                GsErr ->
                    log("GS   ~s → \e[31mfail\e[0m (~p)", [Target, GsErr]),
                    fail
            end,

            {RpcOk + case RpcRes of ok -> 1; _ -> 0 end,
             RpcFail + case RpcRes of fail -> 1; _ -> 0 end,
             GsOk + case GsRes of ok -> 1; _ -> 0 end,
             GsFail + case GsRes of fail -> 1; _ -> 0 end};
        pang ->
            {RpcOk, RpcFail, GsOk, GsFail}
    end,

    #{pings => Pings + 1, pongs => Pongs2, pangs => Pangs2,
      rpc_ok => RpcOk2, rpc_fail => RpcFail2,
      gs_ok => GsOk2, gs_fail => GsFail2}.

%%====================================================================
%% Helpers
%%====================================================================

parse_targets("") -> [];
parse_targets(Env) ->
    [list_to_atom(string:trim(T))
     || T <- string:split(Env, ",", all),
        string:trim(T) =/= ""].

env_int(Key, Default) ->
    case os:getenv(Key) of
        false -> Default;
        "" -> Default;
        Val ->
            try list_to_integer(Val)
            catch _:_ -> Default
            end
    end.

log(Fmt, Args) ->
    Ts = calendar:system_time_to_rfc3339(erlang:system_time(second)),
    io:format("[dist_test ~s] " ++ Fmt ++ "~n", [Ts | Args]).
