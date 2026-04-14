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
-export([peers/0, relays/0, roster/0]).
-export([help/0, about/0]).

%% Interactive-demo helpers
-export([prompt/1, tour/1, tour/2, current_room/0]).

%% Exported for testing
-export([normalize_relay_url/1, strip_url/1, short_node/1, room_key/1, plural/1]).
-export([maybe_connect_peer/1, maybe_append_domain/1, maybe_append_port/2]).
-export([extract_city/1, extract_country/1, country_flag/1]).

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
    ensure_registered(mesh_chat_presence, fun presence_loop/0),
    install_prompt(),
    ok.

-spec disconnect() -> ok.
disconnect() ->
    stop_registered(mesh_chat_presence),
    stop_registered(mesh_chat_rx),
    reset_prompt(),
    persistent_term:erase({mesh_chat, current_room}),
    io:format("\e[36m[mesh]\e[0m Disconnected.~n").

%%====================================================================
%% Rooms
%%====================================================================

-spec join(string()) -> ok.
join(Room) when is_list(Room) ->
    Rx = ensure_rx(),
    pg:join(pg, room_key(Room), Rx),
    persistent_term:put({mesh_chat, rooms}, lists:usort([Room | my_rooms()])),
    set_current_room(Room),
    io:format("\e[32m[chat]\e[0m Joined \e[1m#~s\e[0m~n", [Room]).

-spec leave(string()) -> ok.
leave(Room) when is_list(Room) ->
    maybe_leave_pg(Room),
    Remaining = my_rooms() -- [Room],
    persistent_term:put({mesh_chat, rooms}, Remaining),
    rotate_current_room(Room, Remaining),
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
    say_to_current(current_room(), Message).

%% @private
say_to_current(undefined, _Message) ->
    io:format("\e[31m[chat]\e[0m Join a room first: mesh_chat:join(\"lobby\").~n"),
    ok;
say_to_current(Room, Message) ->
    say(Room, Message).

-spec say(string(), string()) -> ok.
say(Room, Message) when is_list(Room), is_list(Message) ->
    From = display_name(),
    io:format("\e[33m[~ts/#~ts]\e[0m ~ts~n", [From, Room, Message]),
    Rx = whereis(mesh_chat_rx),
    [Pid ! {room_msg, Room, From, Message}
     || Pid <- pg:get_members(pg, room_key(Room)), Pid =/= Rx],
    ok.

%% @private Flag + short nick, e.g. `🇵🇹 alice`. Sender-side so the receiver
%% never needs to look up geography for a message that already knows where
%% it came from.
display_name() ->
    Flag = country_flag(current_country()),
    Nick = nick(),
    case Flag of
        "" -> Nick;
        _  -> [Flag, " ", Nick]
    end.

-spec whisper(atom(), string()) -> ok.
whisper(Node, Message) when is_atom(Node), is_list(Message) ->
    From = display_name(),
    io:format("\e[35m[~ts → ~ts]\e[0m ~ts~n", [From, short_node(Node), Message]),
    case rpc:call(Node, erlang, whereis, [mesh_chat_rx]) of
        Pid when is_pid(Pid) -> Pid ! {whisper, From, Message};
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

%% @doc Formatted list of connected peers with flags, cities, rooms.
%%      Each row fetched via `rpc:call/4' to the peer — one round-trip
%%      per peer, acceptable cost for an on-demand command.
-spec roster() -> [atom()].
roster() ->
    Peers = [node() | nodes()],
    Rows = [roster_row(N) || N <- Peers],
    io:format("~n\e[36m[mesh]\e[0m ~p node(s) in the quartet:~n~n", [length(Peers)]),
    [print_roster_row(R) || R <- Rows],
    io:format("~n"),
    Peers.

%% @private
roster_row(Node) when Node =:= node() ->
    {self_row, Node, current_country(), current_city(),
     persistent_term:get({mesh_chat, rooms}, [])};
roster_row(Node) ->
    Relay = rpc_safe(Node, persistent_term, get,
                     [{mesh_chat, relay}, undefined]),
    Rooms = rpc_safe(Node, persistent_term, get,
                     [{mesh_chat, rooms}, []]),
    {peer_row, Node, extract_country(Relay), extract_city(Relay), Rooms}.

rpc_safe(Node, M, F, A) ->
    case rpc:call(Node, M, F, A, 1500) of
        {badrpc, _} -> undefined;
        Reply       -> Reply
    end.

print_roster_row({self_row, Node, Country, City, Rooms}) ->
    io:format("  \e[32m●\e[0m ~ts \e[1m~ts\e[0m  (you)        \e[90m~ts~ts\e[0m~n",
              [format_flag(Country), short_node(Node), City, fmt_rooms(Rooms)]);
print_roster_row({peer_row, Node, Country, City, Rooms}) ->
    io:format("  \e[32m●\e[0m ~ts \e[1m~ts\e[0m              \e[90m~ts~ts\e[0m~n",
              [format_flag(Country), short_node(Node), City, fmt_rooms(Rooms)]).

format_flag("") -> "  ";
format_flag(CC) -> country_flag(CC).

fmt_rooms([]) -> "";
fmt_rooms(Rs) -> [" · ", string:join([[$# | R] || R <- Rs], " ")].

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
%% Interactive-demo helpers (prompt, tour, current room)
%%====================================================================

%% @doc Shell prompt: `alice@lyon #cars (3)> `. Installed automatically
%% by `connect/2'; reads live state so room / relay changes appear without
%% re-installing. Called by the shell on every new input line.
-spec prompt(list()) -> iolist().
prompt(L) ->
    N = proplists:get_value(history, L, 0),
    io_lib:format("\e[36m~ts\e[0m@\e[33m~ts\e[0m ~ts\e[90m(~p)\e[0m> ",
                  [short_node(node()),
                   current_city(),
                   current_room_display(),
                   N]).

%% @doc One-command demo: connect, join the given room, print a greeting.
%%      mesh_chat:tour("it-palermo", "cars").
-spec tour(string() | binary()) -> ok.
tour(Relay) -> tour(Relay, "lobby").

-spec tour(string() | binary(), string()) -> ok.
tour(Relay, Room) ->
    connect(Relay),
    join(Room),
    timer:sleep(300),
    Peers = nodes(),
    io:format("\e[36m[tour]\e[0m ~p peer(s) so far~n", [length(Peers)]),
    say("I'm in — " ++ current_city()),
    ok.

%% @doc Currently-active room (last joined; reset on leave).
-spec current_room() -> string() | undefined.
current_room() ->
    persistent_term:get({mesh_chat, current_room}, undefined).

%% @private
set_current_room(Room) ->
    persistent_term:put({mesh_chat, current_room}, Room).

%% @private Leaving the active room rotates to another joined room if any.
rotate_current_room(LeftRoom, Remaining) ->
    case current_room() of
        LeftRoom -> rotate_to(Remaining);
        _        -> ok
    end.

rotate_to([]) ->
    persistent_term:erase({mesh_chat, current_room}),
    ok;
rotate_to([Next | _]) ->
    set_current_room(Next).

%% @private
install_prompt() ->
    catch shell:prompt_func({?MODULE, prompt}),
    ok.

reset_prompt() ->
    catch shell:prompt_func(default),
    ok.

%% @private City component of the current relay URL — `relay-it-palermo.…' → `palermo'.
current_city() ->
    extract_city(persistent_term:get({mesh_chat, relay}, undefined)).

%% @doc Extract the city slug from a relay URL. `relay-pt-lisbon.macula.io' → `"lisbon"'.
-spec extract_city(binary() | undefined) -> string().
extract_city(undefined) -> "—";
extract_city(Url) when is_binary(Url) ->
    case re:run(Url, <<"relay-[a-z]{2}-([^.:/]+)">>, [{capture, [1], list}]) of
        {match, [City]} -> City;
        _               -> strip_url(Url)
    end.

%% @doc Extract 2-letter lowercase ISO country code from a relay URL.
%%      `relay-pt-lisbon.macula.io' → `"pt"'. `"" for unrecognised shape.
-spec extract_country(binary() | undefined) -> string().
extract_country(undefined) -> "";
extract_country(Url) when is_binary(Url) ->
    case re:run(Url, <<"relay-([a-z]{2})-">>, [{capture, [1], list}]) of
        {match, [CC]} -> CC;
        _             -> ""
    end.

%% @doc Current node's country derived from its relay URL.
-spec current_country() -> string().
current_country() ->
    extract_country(persistent_term:get({mesh_chat, relay}, undefined)).

%% @doc Convert a 2-letter country code to its Unicode flag emoji.
%%      `"pt"' → `"🇵🇹"'. Returns `"" for anything that isn't two letters.
-spec country_flag(string() | binary()) -> string().
country_flag(CC) when is_binary(CC) ->
    country_flag(binary_to_list(CC));
country_flag([A, B]) when A >= $a, A =< $z, B >= $a, B =< $z ->
    unicode:characters_to_list([regional_indicator(A - $a + $A),
                                regional_indicator(B - $a + $A)]);
country_flag([A, B]) when A >= $A, A =< $Z, B >= $A, B =< $Z ->
    unicode:characters_to_list([regional_indicator(A),
                                regional_indicator(B)]);
country_flag(_) -> "".

regional_indicator(Letter) when Letter >= $A, Letter =< $Z ->
    16#1F1E6 + (Letter - $A).

%% @private
current_room_display() ->
    case current_room() of
        undefined -> "";
        Room      -> io_lib:format("\e[32m#~ts\e[0m ", [Room])
    end.

%%====================================================================
%% Help / About
%%====================================================================

help() ->
    io:format("~n"
        "\e[36m  Mesh Chat — Erlang Distribution over MFRM using QUIC\e[0m~n~n"

        "\e[36m  Connect\e[0m~n"
        "  \e[32mmesh_chat:connect(\"city\").\e[0m        connect to relay-<city>.macula.io~n"
        "  \e[32mmesh_chat:connect(\"c\",\"realm\").\e[0m  connect with an explicit realm~n"
        "  \e[32mmesh_chat:tour(\"city\").\e[0m           connect + join \"lobby\"~n"
        "  \e[32mmesh_chat:tour(\"c\",\"room\").\e[0m      connect + join a named room~n"
        "  \e[32mmesh_chat:disconnect().\e[0m           leave the mesh, reset prompt~n~n"

        "\e[36m  Rooms\e[0m~n"
        "  \e[32mmesh_chat:join(\"room\").\e[0m            join; becomes the current room~n"
        "  \e[32mmesh_chat:leave(\"room\").\e[0m           leave; rotates current~n"
        "  \e[32mmesh_chat:rooms().\e[0m                 rooms you're in + member counts~n"
        "  \e[32mmesh_chat:who(\"room\").\e[0m             who's in a room~n~n"

        "\e[36m  Chat\e[0m~n"
        "  \e[32mmesh_chat:say(\"Hello!\").\e[0m          say in current room~n"
        "  \e[32mmesh_chat:say(\"r\",\"msg\").\e[0m        say in a specific room~n"
        "  \e[32mmesh_chat:whisper(Node,\"m\").\e[0m      private message to one node~n~n"

        "\e[36m  Presence\e[0m~n"
        "  \e[32mmesh_chat:peers().\e[0m                connected BEAM nodes~n"
        "  \e[32mmesh_chat:relays().\e[0m               relay URL you joined via~n"
        "  \e[32mmesh_chat:roster().\e[0m               flag · city · rooms per peer~n"
        "  \e[32mmesh_chat:ping(Node).\e[0m             coloured RTT + route breadcrumb~n~n"

        "\e[36m  Erlang Distribution\e[0m  \e[90m(all work over the QUIC relay mesh)\e[0m~n"
        "  \e[32mnodes().\e[0m                         connected peers~n"
        "  \e[32mnet_adm:ping(Node).\e[0m              liveness ping~n"
        "  \e[32mrpc:call(Node, M, F, A).\e[0m         remote function call~n"
        "  \e[32mgen_server:call({N,Node},m).\e[0m     cross-node gen_server~n"
        "  \e[32mpg:get_members(pg, Group).\e[0m       cluster-wide pg groups~n"
        "  \e[32merlang:monitor(process,{N,Nd}).\e[0m  cross-node monitor~n~n"

        "\e[36m  Shell\e[0m~n"
        "  \e[32mshell:prompt_func(default).\e[0m      reset prompt to default~n"
        "  \e[90mCtrl-G then q\e[0m                       break out of a stuck shell~n"
        "  \e[90mq().\e[0m                               graceful BEAM shutdown~n~n"

        "\e[36m  Info\e[0m~n"
        "  \e[32mmesh_chat:help().\e[0m                 this screen~n"
        "  \e[32mmesh_chat:about().\e[0m                what is MFRM?~n~n").

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

%% Presence interval — re-announce every 30s. This makes discovery
%% self-healing: if a peer's mesh_client silently reconnects, our
%% next announcement re-introduces us and peers will re-ping us.
-define(PRESENCE_INTERVAL_MS, 30_000).

%% Long-lived presence process. Subscribes once, then re-announces
%% periodically so the mesh stays aware of us across silent reconnects.
presence_loop() ->
    %% Give join_mesh a moment to settle before subscribing
    timer:sleep(1000),
    Client = macula_dist_relay:get_mesh_client(),
    subscribe_presence(Client),
    announce_forever(Client).

announce_forever(Client) ->
    announce(Client),
    receive
        stop -> ok
    after ?PRESENCE_INTERVAL_MS ->
        announce_forever(macula_dist_relay:get_mesh_client())
    end.

subscribe_presence(undefined) -> ok;
subscribe_presence(Client) ->
    macula_mesh_client:subscribe(Client, ?PRESENCE_TOPIC,
        fun(Msg) -> handle_peer_announcement(Msg) end).

announce(undefined) -> ok;
announce(Client) ->
    Payload = iolist_to_binary(json:encode(#{<<"node">> => atom_to_binary(node())})),
    macula_mesh_client:publish(Client, ?PRESENCE_TOPIC, Payload).

handle_peer_announcement(Msg) ->
    Node = extract_node(macula_dist_relay:extract_payload(Msg)),
    maybe_connect_peer(binary_to_atom(Node)).

extract_node(#{<<"node">> := N}) -> N;
extract_node(Bin) when is_binary(Bin) -> extract_node(json:decode(Bin)).

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
            io:format("\e[33m[~ts/#~ts]\e[0m ~ts~n", [From, Room, Message]);
        {whisper, From, Message} ->
            io:format("\e[35m[~ts → you]\e[0m ~ts~n", [From, Message]);
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
              "  \e[36mRTT: ~s  \e[90m(Erlang RPC over QUIC relay mesh)\e[0m~n~n",
              [short_node(Node), strip_url(TheirRelay), color_rtt(Rtt)]).

%% Colour bands: green <30ms (same city), yellow <100ms (same continent),
%% red beyond. Matches what a BEAM audience expects visually for a "fast
%% round-trip" indicator in a live demo.
color_rtt(Rtt) when Rtt < 30 ->
    io_lib:format("\e[32m\e[1m~.1f ms\e[0m", [Rtt]);
color_rtt(Rtt) when Rtt < 100 ->
    io_lib:format("\e[33m\e[1m~.1f ms\e[0m", [Rtt]);
color_rtt(Rtt) ->
    io_lib:format("\e[31m\e[1m~.1f ms\e[0m", [Rtt]).

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
    Host2 = maybe_prepend_relay(Host),
    Host3 = maybe_append_domain(Host2),
    maybe_append_port(Host3, Port).

%% Short-form convenience: `it-palermo' → `relay-it-palermo'.
%% Only applied when the host has no dot (i.e. the user typed a bare name);
%% FQDNs and names already starting with `relay-' are left alone.
maybe_prepend_relay(<<"relay-", _/binary>> = H) -> H;
maybe_prepend_relay(H) ->
    case binary:match(H, <<".">>) of
        nomatch -> <<"relay-", H/binary>>;
        _       -> H
    end.

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
