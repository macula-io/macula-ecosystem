%%%-------------------------------------------------------------------
%%% @doc Interactive mesh chat — Erlang distribution over QUIC relay mesh.
%%%
%%% Auto-connects on boot if MACULA_RELAY env var is set.
%%% All Erlang distribution primitives work transparently:
%%% gen_server:call, rpc:call, pg groups, monitors — tunneled
%%% through the relay mesh over QUIC/HTTP3.
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

%%====================================================================
%% Boot — called automatically from start-node.sh via -eval
%%====================================================================

boot() ->
    Relay = case os:getenv("MACULA_RELAY") of
        false -> undefined;
        "" -> undefined;
        Url -> list_to_binary(Url)
    end,
    case Relay of
        undefined ->
            io:format("\e[31m[mesh]\e[0m No MACULA_RELAY set. Use mesh_chat:connect(\"relay-xx-city.macula.io\").~n");
        _ ->
            connect(Relay),
            join("lobby")
    end,
    ok.

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

    case pg:start(pg) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,

    case macula:join_mesh(#{relays => [RelayUrl], realm => Realm}) of
        ok ->
            persistent_term:put({mesh_chat, relay}, RelayUrl),
            print_banner(RelayUrl);
        {error, Reason} ->
            io:format("\e[31m[mesh]\e[0m Connection failed: ~p~n", [Reason]),
            error(Reason)
    end,

    %% Start receiver if not running
    case whereis(mesh_chat_rx) of
        undefined ->
            Pid = spawn(fun() -> rx_loop() end),
            register(mesh_chat_rx, Pid);
        _ -> ok
    end,
    ok.

-spec disconnect() -> ok.
disconnect() ->
    case whereis(mesh_chat_rx) of
        undefined -> ok;
        Pid -> exit(Pid, shutdown)
    end,
    io:format("\e[36m[mesh]\e[0m Disconnected.~n"),
    ok.

%%====================================================================
%% Rooms
%%====================================================================

-spec join(string()) -> ok.
join(Room) when is_list(Room) ->
    Key = room_key(Room),
    Rx = ensure_rx(),
    pg:join(pg, Key, Rx),
    persistent_term:put({mesh_chat, rooms},
        lists:usort([Room | my_rooms()])),
    io:format("\e[32m[chat]\e[0m Joined \e[1m#~s\e[0m~n", [Room]),
    ok.

-spec leave(string()) -> ok.
leave(Room) when is_list(Room) ->
    Key = room_key(Room),
    case whereis(mesh_chat_rx) of
        undefined -> ok;
        Rx -> pg:leave(pg, Key, Rx)
    end,
    persistent_term:put({mesh_chat, rooms},
        my_rooms() -- [Room]),
    io:format("\e[36m[chat]\e[0m Left #~s~n", [Room]),
    ok.

-spec rooms() -> [string()].
rooms() ->
    Rs = my_rooms(),
    io:format("\e[36m[chat]\e[0m ~p room(s):~n", [length(Rs)]),
    lists:foreach(fun(R) ->
        Count = length(pg:get_members(pg, room_key(R))),
        io:format("  \e[36m#\e[0m~s (~p member~s)~n",
                  [R, Count, plural(Count)])
    end, Rs),
    Rs.

-spec who(string()) -> [atom()].
who(Room) when is_list(Room) ->
    Members = pg:get_members(pg, room_key(Room)),
    Nodes = lists:usort([node(P) || P <- Members]),
    io:format("\e[36m[chat]\e[0m #~s — ~p member(s):~n", [Room, length(Nodes)]),
    lists:foreach(fun(N) ->
        io:format("  \e[36m●\e[0m ~s~n", [short_node(N)])
    end, Nodes),
    Nodes.

%%====================================================================
%% Messaging
%%====================================================================

-spec say(string()) -> ok.
say(Message) when is_list(Message) ->
    case my_rooms() of
        [Room] -> say(Room, Message);
        [] -> io:format("\e[31m[chat]\e[0m Join a room first: mesh_chat:join(\"lobby\").~n");
        Rs -> io:format("\e[31m[chat]\e[0m In ~p rooms — use mesh_chat:say(\"room\", \"msg\").~n", [length(Rs)])
    end,
    ok.

-spec say(string(), string()) -> ok.
say(Room, Message) when is_list(Room), is_list(Message) ->
    Nick = nick(),
    io:format("\e[33m[~s/#~s]\e[0m ~s~n", [Nick, Room, Message]),
    Rx = whereis(mesh_chat_rx),
    Members = pg:get_members(pg, room_key(Room)) -- [Rx],
    lists:foreach(fun(Pid) ->
        Pid ! {room_msg, Room, Nick, Message}
    end, Members),
    ok.

-spec whisper(atom(), string()) -> ok.
whisper(Node, Message) when is_atom(Node), is_list(Message) ->
    Nick = nick(),
    io:format("\e[35m[~s → ~s]\e[0m ~s~n", [Nick, short_node(Node), Message]),
    case rpc:call(Node, erlang, whereis, [mesh_chat_rx]) of
        Pid when is_pid(Pid) ->
            Pid ! {whisper, Nick, Message};
        _ ->
            io:format("\e[31m[chat]\e[0m ~p not in chat~n", [Node])
    end,
    ok.

%%====================================================================
%% Status
%%====================================================================

-spec peers() -> [atom()].
peers() ->
    Connected = nodes(),
    io:format("\e[36m[mesh]\e[0m ~p peer(s):~n", [length(Connected)]),
    lists:foreach(fun(N) ->
        io:format("  \e[36m●\e[0m ~s~n", [short_node(N)])
    end, Connected),
    Connected.

-spec relays() -> [binary()].
relays() ->
    case persistent_term:get({mesh_chat, relay}, undefined) of
        undefined ->
            io:format("\e[36m[mesh]\e[0m Not connected~n"), [];
        Url ->
            io:format("\e[36m[mesh]\e[0m Relay: ~s~n", [Url]), [Url]
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
            T1 = erlang:monotonic_time(microsecond),
            Rtt = (T1 - T0) / 1000,

            SameRelay = MyRelay =:= TheirRelay,

            io:format("~n"),
            io:format("  \e[32m●\e[0m \e[1m~s\e[0m  via ~s~n", [nick(), strip_url(MyRelay)]),
            case SameRelay of
                true ->
                    io:format("  \e[90m│\e[0m \e[90msame relay\e[0m~n");
                false ->
                    io:format("  \e[90m│\e[0m \e[90m↕ QUIC tunnel (TLS 1.3)\e[0m~n"),
                    io:format("  \e[90m│\e[0m \e[90m↕ relay mesh peering\e[0m~n"),
                    io:format("  \e[90m│\e[0m \e[90m↕ QUIC tunnel (TLS 1.3)\e[0m~n")
            end,
            io:format("  \e[32m●\e[0m \e[1m~s\e[0m  via ~s~n", [short_node(Node), strip_url(TheirRelay)]),
            io:format("~n"),
            io:format("  \e[36mRTT: \e[1m~.1fms\e[0m  \e[90m(Erlang RPC over QUIC relay mesh)\e[0m~n", [Rtt]),
            io:format("~n")
    end,
    ok.

%%====================================================================
%% Help
%%====================================================================

help() ->
    io:format("~n"),
    io:format("\e[36m  Mesh Chat — Erlang Distribution over MFRM using QUIC\e[0m~n"),
    io:format("~n"),
    io:format("\e[36m  Chat\e[0m~n"),
    io:format("  \e[32mmesh_chat:join(\"room\").\e[0m          join a room~n"),
    io:format("  \e[32mmesh_chat:say(\"Hello!\").\e[0m        say in current room~n"),
    io:format("  \e[32mmesh_chat:say(\"r\",\"msg\").\e[0m      say in specific room~n"),
    io:format("  \e[32mmesh_chat:who(\"room\").\e[0m          who's in a room~n"),
    io:format("  \e[32mmesh_chat:whisper(Node,\"m\").\e[0m    private message~n"),
    io:format("  \e[32mmesh_chat:ping(Node).\e[0m           RTT over mesh~n"),
    io:format("~n"),
    io:format("\e[36m  Erlang Distribution\e[0m  \e[90m(all work over the QUIC relay mesh)\e[0m~n"),
    io:format("  \e[32mnodes().\e[0m                        connected peers~n"),
    io:format("  \e[32mnet_adm:ping(Node).\e[0m             ping a node~n"),
    io:format("  \e[32mrpc:call(Node, M, F, A).\e[0m        remote function call~n"),
    io:format("  \e[32mgen_server:call({N,Node},m).\e[0m    cross-node gen_server~n"),
    io:format("  \e[32mpg:get_members(pg, Group).\e[0m      cluster-wide pg groups~n"),
    io:format("  \e[32merlang:monitor(process,{N,Nd}).\e[0m cross-node monitor~n"),
    io:format("~n"),
    io:format("  \e[32mmesh_chat:about().\e[0m              what is MFRM?~n"),
    io:format("~n"),
    ok.

about() ->
    io:format("~n"),
    io:format("\e[36m  Macula Federated Relay Mesh (MFRM)\e[0m~n"),
    io:format("~n"),
    io:format("  A decentralized relay mesh where \e[1mnodes never talk directly\e[0m.~n"),
    io:format("  Every message routes through lightweight relay servers.~n"),
    io:format("  Relays are \e[1mstateless\e[0m — they hold no data.~n"),
    io:format("  When one dies, nodes reroute in seconds. Automatically.~n"),
    io:format("~n"),
    io:format("  \e[1mTransport\e[0m    QUIC/HTTP3 over UDP — NAT-friendly, 0-RTT~n"),
    io:format("  \e[1mSecurity\e[0m     TLS 1.3, AES-256-GCM per hop~n"),
    io:format("  \e[1mRouting\e[0m      Full mesh peering + Bloom filter forwarding~n"),
    io:format("  \e[1mDiscovery\e[0m    Geographic IPv6, RTT-ranked relay selection~n"),
    io:format("  \e[1mHealth\e[0m       SWIM protocol for relay liveness~n"),
    io:format("  \e[1mRuntime\e[0m      Erlang/OTP — 2M concurrent processes per node~n"),
    io:format("  \e[1mDist\e[0m         -proto_dist macula — Erlang dist over mesh~n"),
    io:format("~n"),
    io:format("  \e[1mCost\e[0m  A relay is a 4 EUR/month VPS or a Raspberry Pi.~n"),
    io:format("        A data center is a 200M EUR facility.~n"),
    io:format("        \e[90mYou can't make data centers indestructible.\e[0m~n"),
    io:format("        \e[1mYou can make relays disposable.\e[0m~n"),
    io:format("~n"),
    io:format("  \e[90mOpen source — Apache-2.0 — hex.pm/packages/macula\e[0m~n"),
    io:format("  \e[90mmacula.io — github.com/macula-io/macula\e[0m~n"),
    io:format("~n"),
    ok.

%%====================================================================
%% Internal
%%====================================================================

print_banner(RelayUrl) ->
    Node = node(),
    OtpVsn = erlang:system_info(otp_release),
    RelayHost = strip_url(RelayUrl),

    %% Resolve relay IPv6
    RelayHostStr = case RelayHost of
        L when is_list(L) -> L;
        B when is_binary(B) -> binary_to_list(B)
    end,
    IPv6 = case inet:getaddr(RelayHostStr, inet6) of
        {ok, Addr} -> inet:ntoa(Addr);
        _ -> "unknown"
    end,

    io:format("~n"),
    io:format("\e[36m  Macula Mesh Chat\e[0m~n"),
    io:format("\e[90m  Erlang distribution over Macula mesh using QUIC\e[0m~n"),
    io:format("~n"),
    io:format("  Node:      \e[33m~s\e[0m~n", [Node]),
    io:format("  Relay:     \e[33m~s\e[0m~n", [RelayHost]),
    io:format("  IPv6:      \e[90m~s\e[0m~n", [IPv6]),
    io:format("  Transport: \e[90mQUIC/HTTP3 (UDP 4433, TLS 1.3)\e[0m~n"),
    io:format("  Runtime:   \e[90mErlang/OTP ~s | -proto_dist macula\e[0m~n", [OtpVsn]),
    io:format("~n"),
    io:format("  \e[32mmesh_chat:say(\"Hello!\").\e[0m    say in current room~n"),
    io:format("  \e[32mmesh_chat:who(\"lobby\").\e[0m     who's here?~n"),
    io:format("  \e[32mmesh_chat:peers().\e[0m          connected peers~n"),
    io:format("  \e[32mmesh_chat:ping(Node).\e[0m       measure RTT over mesh~n"),
    io:format("  \e[32mmesh_chat:help().\e[0m           all commands~n"),
    io:format("~n").

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
        undefined ->
            Pid = spawn(fun() -> rx_loop() end),
            register(mesh_chat_rx, Pid),
            Pid;
        Pid -> Pid
    end.

nick() -> short_node(node()).

short_node(Node) ->
    case string:split(atom_to_list(Node), "@") of
        [Name | _] -> Name;
        _ -> atom_to_list(Node)
    end.

room_key(Room) -> {mesh_chat_room, Room}.

my_rooms() -> persistent_term:get({mesh_chat, rooms}, []).

plural(1) -> "";
plural(_) -> "s".

normalize_relay_url(<<"https://", _/binary>> = Url) -> Url;
normalize_relay_url(<<"http://", _/binary>> = Url) -> Url;
normalize_relay_url(Host) ->
    Port = list_to_binary(os:getenv("MACULA_QUIC_PORT", "4433")),
    case binary:match(Host, <<":">>) of
        {_, _} -> <<"https://", Host/binary>>;
        nomatch -> <<"https://", Host/binary, ":", Port/binary>>
    end.

strip_url(<<"https://", Rest/binary>>) -> strip_port(Rest);
strip_url(<<"http://", Rest/binary>>) -> strip_port(Rest);
strip_url(Url) when is_binary(Url) -> strip_port(Url);
strip_url(_) -> "unknown".

strip_port(Host) ->
    case binary:split(Host, <<":">>) of
        [H | _] -> binary_to_list(H);
        _ -> binary_to_list(Host)
    end.
