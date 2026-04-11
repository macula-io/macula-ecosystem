%%%-------------------------------------------------------------------
%%% @doc Interactive mesh chat — Erlang distribution over QUIC relay mesh.
%%%
%%% Auto-connects on boot if MACULA_RELAY env var is set.
%%% Peer discovery via mesh pub/sub: nodes announce on _chat.presence,
%%% others auto-ping to establish Erlang distribution. pg groups,
%%% rpc:call, gen_server:call then work transparently.
%%%
%%% Quick start:
%%%   mesh_chat:join("lobby").
%%%   mesh_chat:say("Hello from the mesh!").
%%%   mesh_chat:who("lobby").
%%%   mesh_chat:peers().
%%%   mesh_chat:ping('bob@127.0.0.1').
%%% @end
%%%-------------------------------------------------------------------
-module(mesh_chat).

-export([boot/0]).
-export([connect/1, connect/2, disconnect/0]).
-export([join/1, leave/1, rooms/0, who/1]).
-export([ping/1]).
-export([say/1, say/2, whisper/2]).
-export([peers/0, relays/0]).
-export([help/0, about/0]).

%% Exported for testing
-export([normalize_relay_url/1, strip_url/1, short_node/1, room_key/1, plural/1]).
-export([maybe_connect_peer/1, maybe_append_domain/1, maybe_append_port/2]).

-define(PRESENCE_TOPIC, <<"_chat.presence">>).

%%====================================================================
%% Boot
%%====================================================================

boot() ->
    case os:getenv("MACULA_RELAY") of
        Url when Url =/= false, Url =/= "" ->
            connect(list_to_binary(Url)),
            join("lobby");
        _ ->
            io:format("\e[31m[mesh]\e[0m No MACULA_RELAY set. "
                      "Use mesh_chat:connect(\"relay-xx-city\").~n")
    end.

%%====================================================================
%% Connection
%%====================================================================

-spec connect(string() | binary()) -> ok.
connect(Relay) ->
    connect(Relay, <<"io.macula">>).

-spec connect(string() | binary(), binary()) -> ok.
connect(Relay, Realm) when is_list(Relay) ->
    connect(list_to_binary(Relay), Realm);
connect(Relay, Realm) ->
    RelayUrl = normalize_relay_url(Relay),
    ensure_pg(),
    join_mesh(RelayUrl, Realm),
    print_banner(RelayUrl),
    ensure_registered(mesh_chat_rx, fun rx_loop/0),
    spawn(fun() -> start_presence() end),
    ok.

-spec disconnect() -> ok.
disconnect() ->
    stop_registered(mesh_chat_rx),
    io:format("\e[36m[mesh]\e[0m Disconnected.~n").

%%====================================================================
%% Rooms
%%====================================================================

-spec join(string()) -> ok.
join(Room) when is_list(Room) ->
    Rx = ensure_rx(),
    pg:join(pg, room_key(Room), Rx),
    persistent_term:put({mesh_chat, rooms}, lists:usort([Room | my_rooms()])),
    io:format("\e[32m[chat]\e[0m Joined \e[1m#~s\e[0m~n", [Room]).

-spec leave(string()) -> ok.
leave(Room) when is_list(Room) ->
    maybe_leave_pg(Room),
    persistent_term:put({mesh_chat, rooms}, my_rooms() -- [Room]),
    io:format("\e[36m[chat]\e[0m Left #~s~n", [Room]).

-spec rooms() -> [string()].
rooms() ->
    Rs = my_rooms(),
    io:format("\e[36m[chat]\e[0m ~p room(s):~n", [length(Rs)]),
    [io:format("  \e[36m#\e[0m~s (~p member~s)~n",
               [R, length(pg:get_members(pg, room_key(R))),
                plural(length(pg:get_members(pg, room_key(R))))])
     || R <- Rs],
    Rs.

-spec who(string()) -> [atom()].
who(Room) when is_list(Room) ->
    Nodes = lists:usort([node(P) || P <- pg:get_members(pg, room_key(Room))]),
    io:format("\e[36m[chat]\e[0m #~s — ~p member(s):~n", [Room, length(Nodes)]),
    [io:format("  \e[36m●\e[0m ~s~n", [short_node(N)]) || N <- Nodes],
    Nodes.

%%====================================================================
%% Messaging
%%====================================================================

-spec say(string()) -> ok.
say(Message) when is_list(Message) ->
    case my_rooms() of
        [Room] -> say(Room, Message);
        []     -> io:format("\e[31m[chat]\e[0m Join a room first: mesh_chat:join(\"lobby\").~n");
        Rs     -> io:format("\e[31m[chat]\e[0m In ~p rooms — use mesh_chat:say(\"room\", \"msg\").~n", [length(Rs)])
    end,
    ok.

-spec say(string(), string()) -> ok.
say(Room, Message) when is_list(Room), is_list(Message) ->
    Nick = nick(),
    io:format("\e[33m[~s/#~s]\e[0m ~s~n", [Nick, Room, Message]),
    Rx = whereis(mesh_chat_rx),
    [Pid ! {room_msg, Room, Nick, Message}
     || Pid <- pg:get_members(pg, room_key(Room)), Pid =/= Rx],
    ok.

-spec whisper(atom(), string()) -> ok.
whisper(Node, Message) when is_atom(Node), is_list(Message) ->
    Nick = nick(),
    io:format("\e[35m[~s → ~s]\e[0m ~s~n", [Nick, short_node(Node), Message]),
    case rpc:call(Node, erlang, whereis, [mesh_chat_rx]) of
        Pid when is_pid(Pid) -> Pid ! {whisper, Nick, Message};
        _                    -> io:format("\e[31m[chat]\e[0m ~p not in chat~n", [Node])
    end,
    ok.

%%====================================================================
%% Status
%%====================================================================

-spec peers() -> [atom()].
peers() ->
    Connected = nodes(),
    io:format("\e[36m[mesh]\e[0m ~p peer(s):~n", [length(Connected)]),
    [io:format("  \e[36m●\e[0m ~s~n", [short_node(N)]) || N <- Connected],
    Connected.

-spec relays() -> [binary()].
relays() ->
    case persistent_term:get({mesh_chat, relay}, undefined) of
        undefined -> io:format("\e[36m[mesh]\e[0m Not connected~n"), [];
        Url       -> io:format("\e[36m[mesh]\e[0m Relay: ~s~n", [Url]), [Url]
    end.

%%====================================================================
%% Ping
%%====================================================================

-spec ping(atom()) -> ok.
ping(Node) when is_atom(Node) ->
    MyRelay = persistent_term:get({mesh_chat, relay}, <<"unknown">>),
    io:format("\e[36m[ping]\e[0m Pinging \e[1m~s\e[0m...~n", [short_node(Node)]),
    T0 = erlang:monotonic_time(microsecond),
    case rpc:call(Node, persistent_term, get, [{mesh_chat, relay}, <<"unknown">>]) of
        {badrpc, Reason} ->
            io:format("\e[31m[ping]\e[0m Cannot reach ~p: ~p~n", [Node, Reason]);
        TheirRelay ->
            Rtt = (erlang:monotonic_time(microsecond) - T0) / 1000,
            print_ping_result(MyRelay, TheirRelay, Node, Rtt)
    end,
    ok.

%%====================================================================
%% Help / About
%%====================================================================

help() ->
    io:format("~n"
        "\e[36m  Mesh Chat — Erlang Distribution over MFRM using QUIC\e[0m~n~n"
        "\e[36m  Chat\e[0m~n"
        "  \e[32mmesh_chat:join(\"room\").\e[0m          join a room~n"
        "  \e[32mmesh_chat:say(\"Hello!\").\e[0m        say in current room~n"
        "  \e[32mmesh_chat:say(\"r\",\"msg\").\e[0m      say in specific room~n"
        "  \e[32mmesh_chat:who(\"room\").\e[0m          who's in a room~n"
        "  \e[32mmesh_chat:whisper(Node,\"m\").\e[0m    private message~n"
        "  \e[32mmesh_chat:ping(Node).\e[0m           RTT over mesh~n~n"
        "\e[36m  Erlang Distribution\e[0m  \e[90m(all work over the QUIC relay mesh)\e[0m~n"
        "  \e[32mnodes().\e[0m                        connected peers~n"
        "  \e[32mnet_adm:ping(Node).\e[0m             ping a node~n"
        "  \e[32mrpc:call(Node, M, F, A).\e[0m        remote function call~n"
        "  \e[32mgen_server:call({N,Node},m).\e[0m    cross-node gen_server~n"
        "  \e[32mpg:get_members(pg, Group).\e[0m      cluster-wide pg groups~n"
        "  \e[32merlang:monitor(process,{N,Nd}).\e[0m cross-node monitor~n~n"
        "  \e[32mmesh_chat:about().\e[0m              what is MFRM?~n~n").

about() ->
    io:format("~n"
        "\e[36m  Macula Federated Relay Mesh (MFRM)\e[0m~n~n"
        "  A decentralized relay mesh where \e[1mnodes never talk directly\e[0m.~n"
        "  Every message routes through lightweight relay servers.~n"
        "  Relays are \e[1mstateless\e[0m — they hold no data.~n"
        "  When one dies, nodes reroute in seconds. Automatically.~n~n"
        "  \e[1mTransport\e[0m    QUIC/HTTP3 over UDP — NAT-friendly, 0-RTT~n"
        "  \e[1mSecurity\e[0m     TLS 1.3, AES-256-GCM per hop~n"
        "  \e[1mRouting\e[0m      Full mesh peering + Bloom filter forwarding~n"
        "  \e[1mDiscovery\e[0m    Geographic IPv6, RTT-ranked relay selection~n"
        "  \e[1mHealth\e[0m       SWIM protocol for relay liveness~n"
        "  \e[1mRuntime\e[0m      Erlang/OTP — 2M concurrent processes per node~n"
        "  \e[1mDist\e[0m         -proto_dist macula — Erlang dist over mesh~n~n"
        "  \e[1mCost\e[0m  A relay is a 4 EUR/month VPS or a Raspberry Pi.~n"
        "        A data center is a 200M EUR facility.~n"
        "        \e[90mYou can't make data centers indestructible.\e[0m~n"
        "        \e[1mYou can make relays disposable.\e[0m~n~n"
        "  \e[90mOpen source — Apache-2.0 — hex.pm/packages/macula\e[0m~n"
        "  \e[90mmacula.io — github.com/macula-io/macula\e[0m~n~n").

%%====================================================================
%% Internal — Presence Discovery
%%====================================================================

start_presence() ->
    timer:sleep(1000),
    Client = macula_dist_relay:get_mesh_client(),
    subscribe_presence(Client),
    timer:sleep(1000),
    announce(Client).

subscribe_presence(undefined) -> ok;
subscribe_presence(Client) ->
    macula_mesh_client:subscribe(Client, ?PRESENCE_TOPIC,
        fun(Msg) -> handle_peer_announcement(Msg) end).

announce(undefined) -> ok;
announce(Client) ->
    Payload = iolist_to_binary(json:encode(#{<<"node">> => atom_to_binary(node())})),
    macula_mesh_client:publish(Client, ?PRESENCE_TOPIC, Payload).

handle_peer_announcement(Msg) ->
    Bin = macula_dist_relay:extract_payload(Msg),
    #{<<"node">> := NodeBin} = json:decode(Bin),
    maybe_connect_peer(binary_to_atom(NodeBin)).

maybe_connect_peer(Peer) when Peer =:= node() -> ok;
maybe_connect_peer(Peer) ->
    case lists:member(Peer, nodes()) of
        true  -> ok;
        false -> try_connect(Peer)
    end.

try_connect(Peer) ->
    spawn(fun() ->
        case net_adm:ping(Peer) of
            pong -> io:format("\e[32m[mesh]\e[0m Connected to \e[1m~s\e[0m~n", [short_node(Peer)]);
            pang -> ok
        end
    end).

%%====================================================================
%% Internal — Connection Setup
%%====================================================================

ensure_pg() ->
    case pg:start(pg) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end.

join_mesh(RelayUrl, Realm) ->
    case macula:join_mesh(#{relays => [RelayUrl], realm => Realm}) of
        ok ->
            persistent_term:put({mesh_chat, relay}, RelayUrl);
        {error, Reason} ->
            io:format("\e[31m[mesh]\e[0m Connection failed: ~p~n", [Reason]),
            error(Reason)
    end.

ensure_registered(Name, Fun) ->
    case whereis(Name) of
        undefined ->
            Pid = spawn(Fun),
            register(Name, Pid);
        _ -> ok
    end.

stop_registered(Name) ->
    case whereis(Name) of
        undefined -> ok;
        Pid       -> exit(Pid, shutdown)
    end.

maybe_leave_pg(Room) ->
    case whereis(mesh_chat_rx) of
        undefined -> ok;
        Rx        -> pg:leave(pg, room_key(Room), Rx)
    end.

%%====================================================================
%% Internal — Message Loop
%%====================================================================

rx_loop() ->
    receive
        {room_msg, Room, From, Message} ->
            io:format("\e[33m[~s/#~s]\e[0m ~s~n", [From, Room, Message]);
        {whisper, From, Message} ->
            io:format("\e[35m[~s → you]\e[0m ~s~n", [From, Message]);
        _ -> ok
    end,
    rx_loop().

ensure_rx() ->
    case whereis(mesh_chat_rx) of
        undefined -> ensure_registered(mesh_chat_rx, fun rx_loop/0), whereis(mesh_chat_rx);
        Pid       -> Pid
    end.

%%====================================================================
%% Internal — Display
%%====================================================================

print_banner(RelayUrl) ->
    RelayHost = strip_url(RelayUrl),
    IPv6 = resolve_ipv6(RelayHost),
    OtpVsn = erlang:system_info(otp_release),
    io:format("~n"
        "\e[36m  Macula Mesh Chat\e[0m~n"
        "\e[90m  Erlang distribution over Macula mesh using QUIC\e[0m~n~n"
        "  Node:      \e[33m~s\e[0m~n"
        "  Relay:     \e[33m~s\e[0m~n"
        "  IPv6:      \e[90m~s\e[0m~n"
        "  Transport: \e[90mQUIC/HTTP3 (UDP 4433, TLS 1.3)\e[0m~n"
        "  Runtime:   \e[90mErlang/OTP ~s | -proto_dist macula\e[0m~n~n"
        "  \e[32mmesh_chat:say(\"Hello!\").\e[0m    say in current room~n"
        "  \e[32mmesh_chat:who(\"lobby\").\e[0m     who's here?~n"
        "  \e[32mmesh_chat:peers().\e[0m          connected peers~n"
        "  \e[32mmesh_chat:ping(Node).\e[0m       measure RTT over mesh~n"
        "  \e[32mmesh_chat:help().\e[0m           all commands~n~n",
        [node(), RelayHost, IPv6, OtpVsn]).

print_ping_result(MyRelay, TheirRelay, Node, Rtt) ->
    io:format("~n  \e[32m●\e[0m \e[1m~s\e[0m  via ~s~n", [nick(), strip_url(MyRelay)]),
    print_relay_path(MyRelay =:= TheirRelay),
    io:format("  \e[32m●\e[0m \e[1m~s\e[0m  via ~s~n~n"
              "  \e[36mRTT: \e[1m~.1fms\e[0m  \e[90m(Erlang RPC over QUIC relay mesh)\e[0m~n~n",
              [short_node(Node), strip_url(TheirRelay), Rtt]).

print_relay_path(true) ->
    io:format("  \e[90m│\e[0m \e[90msame relay\e[0m~n");
print_relay_path(false) ->
    io:format("  \e[90m│\e[0m \e[90m↕ QUIC tunnel (TLS 1.3)\e[0m~n"
              "  \e[90m│\e[0m \e[90m↕ relay mesh peering\e[0m~n"
              "  \e[90m│\e[0m \e[90m↕ QUIC tunnel (TLS 1.3)\e[0m~n").

resolve_ipv6(Host) ->
    HostStr = case Host of
        L when is_list(L) -> L;
        B when is_binary(B) -> binary_to_list(B)
    end,
    case inet:getaddr(HostStr, inet6) of
        {ok, Addr} -> inet:ntoa(Addr);
        _          -> "unknown"
    end.

%%====================================================================
%% Internal — Helpers
%%====================================================================

nick() -> short_node(node()).

short_node(Node) ->
    [Name | _] = string:split(atom_to_list(Node), "@"),
    Name.

room_key(Room) -> {mesh_chat_room, Room}.

my_rooms() -> persistent_term:get({mesh_chat, rooms}, []).

plural(1) -> "";
plural(_) -> "s".

normalize_relay_url(<<"https://", _/binary>> = Url) -> Url;
normalize_relay_url(<<"http://", _/binary>> = Url) -> Url;
normalize_relay_url(Host) ->
    Port = list_to_binary(os:getenv("MACULA_QUIC_PORT", "4433")),
    Host2 = maybe_append_domain(Host),
    maybe_append_port(Host2, Port).

maybe_append_domain(Host) ->
    case binary:match(Host, <<".">>) of
        nomatch -> <<Host/binary, ".macula.io">>;
        _       -> Host
    end.

maybe_append_port(Host, Port) ->
    case binary:match(Host, <<":">>) of
        {_, _}  -> <<"https://", Host/binary>>;
        nomatch -> <<"https://", Host/binary, ":", Port/binary>>
    end.

strip_url(<<"https://", Rest/binary>>) -> strip_port(Rest);
strip_url(<<"http://", Rest/binary>>)  -> strip_port(Rest);
strip_url(Url) when is_binary(Url)     -> strip_port(Url);
strip_url(_)                           -> "unknown".

strip_port(Host) ->
    [H | _] = binary:split(Host, <<":">>),
    binary_to_list(H).
