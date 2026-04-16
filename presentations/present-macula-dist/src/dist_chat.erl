%%%-------------------------------------------------------------------
%%% @doc Interactive dist chat — Erlang distribution over a dedicated
%%% QUIC dist-relay.
%%%
%%% Same shell UX as `mesh_chat', but the transport is a raw QUIC
%%% stream through `macula-dist-relay' instead of the station's pub/sub
%%% pipeline. Once connected, everything is standard OTP: `pg' groups
%%% for room membership, direct `!' sends for messages, `rpc:call' and
%%% `gen_server:call' for cross-node operations.
%%%
%%% No station relay, no pub/sub, no MessagePack framing in the dist
%%% hot path. Just raw Erlang distribution bytes tunneled through QUIC.
%%%
%%% Quick start (shell):
%%%   dist_chat:connect().              %% auto-derives URL from geo vars
%%%   dist_chat:ping('bob@host').       %% form cluster
%%%   dist_chat:join("lobby").
%%%   dist_chat:say("Hello from the dist relay!").
%%%   dist_chat:who("lobby").
%%%   dist_chat:peers().
%%%
%%% Or with an explicit URL:
%%%   dist_chat:connect(<<"quic://dist-de-nuremberg.macula.io:4434">>).
%%%
%%% Auto-boot: set MACULA_DIST_RELAY_URL or MACULA_GEO_COUNTRY +
%%% MACULA_GEO_CITY env vars before starting the shell, and
%%% `dist_chat:boot()' connects + joins "lobby" automatically.
%%% @end
%%%-------------------------------------------------------------------
-module(dist_chat).

-export([boot/0]).
-export([connect/0, connect/1, disconnect/0]).
-export([join/1, leave/1, rooms/0, who/1]).
-export([ping/1, peers/0, roster/0]).
-export([say/1, say/2, whisper/2]).
-export([help/0]).

%%====================================================================
%% Boot
%%====================================================================

boot() ->
    Url = dist_test_server:derive_dist_relay_url(),
    boot_with_url(Url).

boot_with_url(undefined) ->
    io:format("\e[31m[dist]\e[0m No dist-relay URL. Set MACULA_DIST_RELAY_URL or "
              "MACULA_GEO_COUNTRY + MACULA_GEO_CITY.~n"
              "  Or: dist_chat:connect(<<\"quic://dist-de-nuremberg.macula.io:4434\">>).~n");
boot_with_url(Url) ->
    connect(Url),
    join("lobby").

%%====================================================================
%% Connection
%%====================================================================

connect() ->
    Url = dist_test_server:derive_dist_relay_url(),
    connect_with_url(Url).

connect(Url) when is_list(Url) ->
    connect(list_to_binary(Url));
connect(Url) when is_binary(Url) ->
    connect_with_url(Url).

connect_with_url(undefined) ->
    io:format("\e[31m[dist]\e[0m Cannot derive URL. Pass one explicitly:~n"
              "  dist_chat:connect(<<\"quic://dist-de-nuremberg.macula.io:4434\">>).~n"),
    {error, no_url};
connect_with_url(Url) ->
    %% Tune OTP dist for WAN latency
    net_kernel:set_net_ticktime(120),
    application:set_env(kernel, net_setuptime, 15),
    ensure_pg(),
    %% The HOST APP starts the client — not the library. macula SDK
    %% provides macula_dist_relay_client:start_link/2; we own the
    %% supervision here (linked to the shell process for demo use).
    start_dist_relay_client(Url),
    ensure_registered(dist_chat_rx, fun rx_loop/0),
    print_banner(Url),
    auto_ping_targets(),
    ok.

disconnect() ->
    stop_registered(dist_chat_rx),
    persistent_term:erase({dist_chat, current_room}),
    io:format("\e[36m[dist]\e[0m Disconnected.~n").

%%====================================================================
%% Cluster
%%====================================================================

ping(Node) when is_atom(Node) ->
    Result = net_adm:ping(Node),
    format_ping(Node, Result),
    Result.

format_ping(Node, pong) ->
    io:format("\e[32m[dist]\e[0m ~s → \e[32mpong\e[0m~n", [short_node(Node)]);
format_ping(Node, pang) ->
    io:format("\e[31m[dist]\e[0m ~s → \e[31mpang\e[0m~n", [short_node(Node)]).

peers() ->
    Ns = lists:sort(nodes()),
    io:format("\e[36m[dist]\e[0m ~p connected peer(s):~n", [length(Ns)]),
    [io:format("  \e[36m●\e[0m ~s~n", [short_node(N)]) || N <- Ns],
    Ns.

roster() ->
    All = [node() | lists:sort(nodes())],
    io:format("\e[36m[dist]\e[0m Cluster (~p node~s):~n",
              [length(All), plural(length(All))]),
    [io:format("  ~s ~s~n",
               [case N =:= node() of true -> "\e[33m→\e[0m"; false -> " " end,
                short_node(N)])
     || N <- All],
    All.

%%====================================================================
%% Rooms (pg groups — standard OTP, works over any Erlang dist)
%%====================================================================

join(Room) when is_list(Room) ->
    Rx = ensure_rx(),
    pg:join(pg, room_key(Room), Rx),
    persistent_term:put({dist_chat, rooms}, lists:usort([Room | my_rooms()])),
    set_current_room(Room),
    Members = length(pg:get_members(pg, room_key(Room))),
    io:format("\e[32m[chat]\e[0m Joined \e[1m#~s\e[0m (~p member~s)~n",
              [Room, Members, plural(Members)]).

leave(Room) when is_list(Room) ->
    maybe_leave_pg(Room),
    Remaining = my_rooms() -- [Room],
    persistent_term:put({dist_chat, rooms}, Remaining),
    rotate_current_room(Room, Remaining),
    io:format("\e[36m[chat]\e[0m Left #~s~n", [Room]).

rooms() ->
    Rs = my_rooms(),
    io:format("\e[36m[chat]\e[0m ~p room(s):~n", [length(Rs)]),
    [io:format("  \e[36m#\e[0m~s (~p member~s)~n",
               [R, length(pg:get_members(pg, room_key(R))),
                plural(length(pg:get_members(pg, room_key(R))))])
     || R <- Rs],
    Rs.

who(Room) when is_list(Room) ->
    Nodes = lists:usort([node(P) || P <- pg:get_members(pg, room_key(Room))]),
    io:format("\e[36m[chat]\e[0m #~s — ~p member(s):~n", [Room, length(Nodes)]),
    [io:format("  \e[36m●\e[0m ~s~n", [short_node(N)]) || N <- Nodes],
    Nodes.

%%====================================================================
%% Messaging
%%====================================================================

say(Message) when is_list(Message) ->
    say_to_current(current_room(), Message).

say(Room, Message) when is_list(Room), is_list(Message) ->
    Msg = #{from => display_name(), room => Room, text => Message, ts => ts()},
    Members = pg:get_members(pg, room_key(Room)),
    [P ! {chat_msg, Msg} || P <- Members, node(P) =/= node()],
    display_chat_msg(Msg).

whisper(Node, Message) when is_atom(Node), is_list(Message) ->
    Msg = #{from => display_name(), to => Node, text => Message, ts => ts()},
    case rpc:call(Node, erlang, whereis, [dist_chat_rx]) of
        Pid when is_pid(Pid) ->
            Pid ! {whisper_msg, Msg},
            io:format("\e[35m[whisper → ~s]\e[0m ~s~n", [short_node(Node), Message]);
        _ ->
            io:format("\e[31m[dist]\e[0m ~s has no dist_chat running~n", [short_node(Node)])
    end.

%%====================================================================
%% Help
%%====================================================================

help() ->
    io:format("~n"
              "\e[1m  dist_chat — Erlang distribution over QUIC dist-relay\e[0m~n"
              "~n"
              "  \e[36mConnection\e[0m~n"
              "    connect()                  Auto-derive URL from geo vars~n"
              "    connect(Url)               Connect to specific dist-relay~n"
              "    disconnect()               Disconnect~n"
              "~n"
              "  \e[36mCluster\e[0m~n"
              "    ping('node@host')          Connect to a peer~n"
              "    peers()                    List connected nodes~n"
              "    roster()                   Full cluster view~n"
              "~n"
              "  \e[36mChat\e[0m~n"
              "    join(\"room\")               Join a chat room~n"
              "    leave(\"room\")              Leave a room~n"
              "    rooms()                    List your rooms~n"
              "    who(\"room\")                List room members~n"
              "    say(\"message\")             Send to current room~n"
              "    say(\"room\", \"message\")     Send to specific room~n"
              "    whisper('node', \"msg\")     Direct message via rpc:call~n"
              "~n"
              "  \e[36mTransport\e[0m: raw QUIC streams via macula-dist-relay~n"
              "  \e[36mMessaging\e[0m: OTP pg groups + direct ! sends~n"
              "  \e[36mNo pub/sub\e[0m: everything is standard Erlang distribution~n~n").

%%====================================================================
%% Internal — connection
%%====================================================================

ensure_pg() ->
    case pg:start(pg) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end.

%% Start the dist_relay_client directly — the library provides the
%% module, the host app (us) owns the process lifecycle.
start_dist_relay_client(Url) ->
    NodeName = atom_to_binary(node()),
    case macula_dist_relay_client:start_link(Url, NodeName) of
        {ok, _Pid} ->
            os:putenv("MACULA_DIST_MODE", "dist_relay"),
            io:format("\e[32m[dist]\e[0m Connected to ~s~n", [Url]);
        {error, {already_started, _Pid}} ->
            os:putenv("MACULA_DIST_MODE", "dist_relay"),
            io:format("\e[32m[dist]\e[0m Already connected~n");
        {error, Reason} ->
            io:format("\e[31m[dist]\e[0m Client failed: ~p~n", [Reason])
    end.

%% If PING_TARGETS env is set (Docker/headless mode), auto-connect.
auto_ping_targets() ->
    case os:getenv("PING_TARGETS") of
        false -> ok;
        "" -> ok;
        Targets ->
            Nodes = [list_to_atom(string:trim(T))
                     || T <- string:split(Targets, ",", all),
                        string:trim(T) =/= ""],
            [spawn(fun() -> timer:sleep(3000), ping(N) end) || N <- Nodes],
            ok
    end.

%%====================================================================
%% Internal — messaging
%%====================================================================

say_to_current(undefined, _Message) ->
    io:format("\e[31m[chat]\e[0m Not in a room. Use dist_chat:join(\"lobby\").~n");
say_to_current(Room, Message) ->
    say(Room, Message).

rx_loop() ->
    receive
        {chat_msg, Msg} ->
            display_chat_msg(Msg),
            rx_loop();
        {whisper_msg, Msg} ->
            display_whisper(Msg),
            rx_loop();
        stop ->
            ok;
        _ ->
            rx_loop()
    end.

display_chat_msg(#{from := From, room := Room, text := Text, ts := Ts}) ->
    io:format("\e[90m~s\e[0m \e[36m#~s\e[0m \e[1m~s\e[0m: ~s~n",
              [Ts, Room, From, Text]).

display_whisper(#{from := From, text := Text, ts := Ts}) ->
    io:format("\e[90m~s\e[0m \e[35m[whisper ← ~s]\e[0m ~s~n", [Ts, From, Text]).

%%====================================================================
%% Internal — state
%%====================================================================

my_rooms() ->
    persistent_term:get({dist_chat, rooms}, []).

current_room() ->
    persistent_term:get({dist_chat, current_room}, undefined).

set_current_room(Room) ->
    persistent_term:put({dist_chat, current_room}, Room).

rotate_current_room(Left, Remaining) ->
    case current_room() of
        Left -> apply_rotation(Remaining);
        _ -> ok
    end.

apply_rotation([Next | _]) -> set_current_room(Next);
apply_rotation([]) -> persistent_term:erase({dist_chat, current_room}).

room_key(Room) ->
    {dist_chat, Room}.

maybe_leave_pg(Room) ->
    Key = room_key(Room),
    case erlang:whereis(dist_chat_rx) of
        undefined -> ok;
        Pid -> pg:leave(pg, Key, Pid)
    end.

ensure_rx() ->
    case erlang:whereis(dist_chat_rx) of
        undefined -> ensure_registered(dist_chat_rx, fun rx_loop/0);
        Pid -> Pid
    end.

%%====================================================================
%% Internal — display
%%====================================================================

display_name() ->
    short_node(node()).

short_node(Node) ->
    [Name | _] = string:split(atom_to_list(Node), "@"),
    Name.

ts() ->
    {{_Y, _M, _D}, {H, Mi, S}} = calendar:local_time(),
    io_lib:format("~2..0b:~2..0b:~2..0b", [H, Mi, S]).

plural(1) -> "";
plural(_) -> "s".

print_banner(Url) ->
    io:format("~n"
              "  \e[1;36m━━━ dist_chat ━━━\e[0m~n"
              "  relay:  ~s~n"
              "  node:   ~s~n"
              "  proto:  raw QUIC streams (no pub/sub)~n"
              "~n"
              "  dist_chat:help() for commands~n~n",
              [Url, node()]).

%%====================================================================
%% Internal — process management
%%====================================================================

ensure_registered(Name, Fun) ->
    case erlang:whereis(Name) of
        undefined ->
            Pid = spawn(Fun),
            register(Name, Pid),
            Pid;
        Pid ->
            Pid
    end.

stop_registered(Name) ->
    case erlang:whereis(Name) of
        undefined -> ok;
        Pid -> Pid ! stop, ok
    end.
