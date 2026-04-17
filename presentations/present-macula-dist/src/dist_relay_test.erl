%%%-------------------------------------------------------------------
%%% @doc Automated dist-relay test — called by scripts/test-dist-relay.sh.
%%%
%%% Two modes:
%%%   dist_relay_test:alice(Url) — connect + wait forever (background node)
%%%   dist_relay_test:bob(Url, AliceNode) — connect, ping alice, report, halt
%%% @end
%%%-------------------------------------------------------------------
-module(dist_relay_test).

-export([alice/1, bob/2]).

alice(Url) ->
    setup(Url),
    io:format("[alice] Connected + identified. Waiting for ping...~n"),
    receive after infinity -> ok end.

bob(Url, AliceNode) ->
    setup(Url),
    io:format("[bob] Connected + identified. Pinging ~s...~n", [AliceNode]),
    timer:sleep(2000),
    Target = list_to_atom(binary_to_list(AliceNode)),
    Result = net_adm:ping(Target),
    io:format("[bob] ping ~s → ~p~n", [AliceNode, Result]),
    handle_result(Result, Target).

%%====================================================================
%% Internal
%%====================================================================

setup(Url) ->
    application:ensure_all_started(macula),
    pg:start(pg),
    %% WAN latency — give handshake more time
    net_kernel:set_net_ticktime(120),
    application:set_env(kernel, net_setuptime, 30),
    NodeName = atom_to_binary(node()),
    io:format("[setup] node=~s, starting client to ~s~n", [NodeName, Url]),
    {ok, _} = macula_dist_relay_client:start_link(Url, NodeName),
    io:format("[setup] client started, registering kernel~n"),
    register_kernel(),
    io:format("[setup] done~n").

register_kernel() ->
    case {erlang:whereis(net_kernel), macula_dist_relay_client:whereis_client()} of
        {Kernel, Client} when is_pid(Kernel), is_pid(Client) ->
            ok = macula_dist_relay_client:set_kernel(Client, Kernel),
            io:format("[setup] kernel_pid registered with client~n");
        _ ->
            io:format("[setup] WARNING: could not register kernel~n")
    end.

handle_result(pong, Target) ->
    RpcResult = rpc:call(Target, erlang, node, []),
    io:format("[bob] rpc:call(~s, erlang, node, []) → ~p~n", [Target, RpcResult]),
    io:format("~n━━━ RESULT: PASS ━━━~n"),
    io:format("  dist-over-relay is working!~n"),
    io:format("  nodes() = ~p~n~n", [nodes()]),
    halt(0);
handle_result(pang, Target) ->
    io:format("~n━━━ RESULT: FAIL (pang) ━━━~n"),
    io:format("  target:          ~s~n", [Target]),
    io:format("  MACULA_DIST_MODE: ~s~n", [os:getenv("MACULA_DIST_MODE")]),
    io:format("  proto_dist:      ~p~n", [init:get_argument(proto_dist)]),
    print_client_status(),
    halt(1).

print_client_status() ->
    case macula_dist_relay_client:whereis_client() of
        undefined ->
            io:format("  client:          NOT RUNNING~n");
        Pid ->
            Status = macula_dist_relay_client:status(Pid),
            io:format("  client status:   ~p~n", [Status])
    end.
