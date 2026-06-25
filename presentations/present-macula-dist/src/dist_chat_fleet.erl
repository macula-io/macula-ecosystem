%%%-------------------------------------------------------------------
%%% @doc Fully-headless multi-participant chat fleet test.
%%%
%%% Spawned per node by scripts/test-chat-fleet.sh. Each participant:
%%%   1. Connects to a dist-relay over QUIC
%%%   2. Pings the seed (unless it IS the seed) to form the dist cluster
%%%   3. Joins the shared room via pg (participant pid IS the pg member,
%%%      so chat messages arrive in the participant's mailbox directly)
%%%   4. Broadcasts one message into the room
%%%   5. Waits until it has received one message from every OTHER
%%%      participant (quorum), or times out
%%%   6. Prints PASS / FAIL with diagnostics and halts
%%%
%%% The process exit code drives the orchestrator's verdict.
%%% @end
%%%-------------------------------------------------------------------
-module(dist_chat_fleet).

-export([participant/1]).

-define(SCOPE, pg).

%% Single-argument entry point so the shell eval is readable on a command line.
%% Opts map:
%%   url       :: binary()   — relay URL, e.g. <<"quic://dist-de-nuremberg.macula.io:4434">>
%%   seed      :: atom()     — node() of the seed; each non-seed pings it
%%   room      :: string()   — shared room name
%%   peers     :: [atom()]   — expected peer node names (incl. self)
%%   quorum_ms :: pos_integer() — deadline for receiving peer messages
participant(Opts) ->
    Url       = maps:get(url,       Opts),
    Seed      = maps:get(seed,      Opts),
    Room      = maps:get(room,      Opts),
    Peers     = maps:get(peers,     Opts),
    QuorumMs  = maps:get(quorum_ms, Opts, 60_000),

    logf("booting with ~p peer~s, room=#~s seed=~s url=~s",
         [length(Peers), plural(length(Peers)), Room, Seed, Url]),

    ok = wan_tuning(),
    ok = connect_to_relay(Url),
    ok = ping_seed(Seed),
    ok = join_room(Room),

    ExpectedFrom = lists:sort(Peers) -- [node()],
    ExpectedCount = length(ExpectedFrom),

    ok = announce(Room),

    case await_quorum(ExpectedFrom, QuorumMs) of
        {ok, Received} ->
            logf("RESULT: PASS — got ~p/~p peer messages: ~p",
                 [length(Received), ExpectedCount, Received]),
            halt(0);
        {timeout, Received} ->
            Missing = ExpectedFrom -- Received,
            logf("RESULT: FAIL — missing ~p peer message~s from: ~p",
                 [length(Missing), plural(length(Missing)), Missing]),
            log_diag(),
            halt(1)
    end.

%%====================================================================
%% Boot steps
%%====================================================================

wan_tuning() ->
    net_kernel:set_net_ticktime(120),
    application:set_env(kernel, net_setuptime, 30),
    ok.

connect_to_relay(Url) ->
    application:ensure_all_started(macula),
    case pg:start(?SCOPE) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,
    os:putenv("MACULA_DIST_MODE", "dist_relay"),
    NodeName = atom_to_binary(node()),
    {ok, Client} = macula_dist_relay_client:start_link(Url, NodeName),
    ok = macula_dist_relay_client:set_kernel(Client, whereis(net_kernel)),
    ok = await_identified(Client, 10_000),
    logf("client identified on relay"),
    ok.

await_identified(Client, DeadlineMs) when DeadlineMs =< 0 ->
    {error, {identify_timeout, macula_dist_relay_client:status(Client)}};
await_identified(Client, DeadlineMs) ->
    check_identified(macula_dist_relay_client:status(Client), Client, DeadlineMs).

check_identified(#{identified := true}, _Client, _Remaining) -> ok;
check_identified(_, Client, Remaining) ->
    timer:sleep(200),
    await_identified(Client, Remaining - 200).

ping_seed(Seed) when Seed =:= node() ->
    logf("I am the seed — nothing to ping"),
    ok;
ping_seed(Seed) ->
    ping_with_retry(Seed, 5).

ping_with_retry(_Seed, 0) ->
    error(seed_unreachable);
ping_with_retry(Seed, N) ->
    case net_adm:ping(Seed) of
        pong ->
            logf("seed ~s → pong", [Seed]),
            ok;
        pang ->
            logf("seed ~s → pang (retry ~p)", [Seed, N]),
            timer:sleep(1000),
            ping_with_retry(Seed, N - 1)
    end.

join_room(Room) ->
    %% The participant's OWN pid is the pg member so {chat_msg, _}
    %% messages arrive in the receive loop directly.
    pg:join(?SCOPE, {dist_chat, Room}, self()),
    logf("joined #~s (initial pg members: ~p)",
         [Room, length(pg:get_members(?SCOPE, {dist_chat, Room}))]),
    ok.

%%====================================================================
%% Messaging
%%====================================================================

announce(Room) ->
    %% Give pg + global a moment to sync across peers that are still
    %% completing their dist handshake
    timer:sleep(3000),
    Text = ["hello from ", atom_to_list(node())],
    Msg = #{from => node(), room => Room, text => iolist_to_binary(Text)},
    Members = pg:get_members(?SCOPE, {dist_chat, Room}),
    [P ! {chat_msg, Msg} || P <- Members, node(P) =/= node()],
    Remote = length([P || P <- Members, node(P) =/= node()]),
    logf("announced to ~p remote member~s (~p pg members total)",
         [Remote, plural(Remote), length(Members)]),
    ok.

await_quorum(ExpectedFrom, TotalMs) ->
    Deadline = erlang:monotonic_time(millisecond) + TotalMs,
    collect(ExpectedFrom, [], Deadline).

collect(Expected, Acc, _Deadline) when length(Acc) >= length(Expected) ->
    {ok, lists:sort(Acc)};
collect(Expected, Acc, Deadline) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    collect_with_budget(Remaining, Expected, Acc, Deadline).

collect_with_budget(Remaining, _Expected, Acc, _Deadline) when Remaining =< 0 ->
    {timeout, lists:sort(Acc)};
collect_with_budget(Remaining, Expected, Acc, Deadline) ->
    receive
        {chat_msg, #{from := From}} ->
            collect_from(lists:member(From, Acc), From, Expected, Acc, Deadline)
    after min(Remaining, 2000) ->
        logf("still waiting (~p/~p from: ~p) ...",
             [length(Acc), length(Expected), Expected -- Acc]),
        collect(Expected, Acc, Deadline)
    end.

collect_from(true, _From, Expected, Acc, Deadline) ->
    collect(Expected, Acc, Deadline);
collect_from(false, From, Expected, Acc, Deadline) ->
    logf("received chat from ~s (~p/~p)",
         [From, length(Acc) + 1, length(Expected)]),
    collect(Expected, [From | Acc], Deadline).

%%====================================================================
%% Diagnostics
%%====================================================================

log_diag() ->
    logf("nodes() = ~p", [nodes()]),
    Client = macula_dist_relay_client:whereis_client(),
    case Client of
        undefined -> logf("dist_relay_client: NOT RUNNING");
        Pid       -> logf("client status: ~p", [macula_dist_relay_client:status(Pid)])
    end,
    logf("global:registered_names/0 = ~p", [lists:sort(global:registered_names())]),
    ok.

%%====================================================================
%% Utilities
%%====================================================================

logf(Fmt) -> logf(Fmt, []).
logf(Fmt, Args) ->
    {{_, _, _}, {H, Mi, S}} = calendar:local_time(),
    io:format("~2..0b:~2..0b:~2..0b [~s] " ++ Fmt ++ "~n",
              [H, Mi, S, node() | Args]).

plural(1) -> "";
plural(_) -> "s".
