# BEAM-audience demo improvement ideas

*Captured 2026-04-14. Curated list of suggestions for making the
interactive mesh_chat demo land with Erlang / Elixir crowds. Tiered by
effort vs impact. Items marked ★ are quick wins.*

---

## Tier 1 — quick wins (★), 20-50 LoC each

1. **`mesh_chat:obs/0`** — one-call `observer_cli:start()` fallback to
   `observer:start()`. Drill into live gen_statems, message queues,
   ETS. BEAM folks get visceral satisfaction from watching processes.

2. **`mesh_chat:trace_wire/1`** — wraps
   `recon_trace:calls({macula_peer_client, async_call, 7}, 50, [{time, Mins*60000}])`.
   Frames flowing live. The "BEAM tracing is magic" moment.

3. **`mesh_chat:roster/0`** (*shipped*) — IRC-style `/names`: flag emoji,
   city, rooms, RTT, uptime per peer.

4. **Colored RTT in `ping/1`** (*shipped*) — green <30 ms, yellow <100 ms,
   red >100 ms. Print the full route as breadcrumbs.

5. **`mesh_chat:whoami/0`** — self-status card: node, relay, IPv6 addr,
   process count, memory, uptime. Nice for the "who am I" moment.

## Tier 2 — the "wow" demonstrations

6. **Kill a relay mid-chat** — `mesh_chat:kill_relay("lyon")` publishes
   `_relay.admin.kill` to the admin API. Chat interrupts ~3 s, mesh
   reroutes, conversation resumes. "Datacenter destroyed. Mesh keeps
   going."

7. **Hot code reload across the mesh** — edit `mesh_chat.erl`,
   `l(mesh_chat)` locally, then
   `rpc:multicall(nodes(), c, l, [mesh_chat])`. New feature appears on
   every peer without disconnection.

8. **Latency comparison table** — `mesh_chat:bench/0` times 1k messages
   over: local pg, same-city mesh RPC, cross-country, cross-Europe.
   Side-by-side numbers. Audiences love concrete numbers.

9. **`global:trans/2` across the mesh** — distributed lock demo. Two
   audience nodes try to claim a chat-admin role; only one wins.
   `global` works transparently over `-proto_dist macula`.

10. **Cross-mesh `rpc:call`** —
    `rpc:call('bob@host00.lab', erlang, statistics, [run_queue])`.
    See bob's scheduler queue from alice's shell. Transparency of
    dist-over-QUIC sinks in.

## Tier 3 — richer narratives

11. **Partition-heal** — `iptables -I OUTPUT -d $relay_ip -j DROP` on
    one node. `global` detects partition. Remove rule → heal within
    seconds. Optional auto script:
    `mesh_chat:simulate_partition(Secs)`.

12. **Flag emojis on presence** (*shipped*) — parse country from
    `relay-XX-…`, map to Unicode regional-indicator flag. Pure polish,
    high visual reward.

13. **`mesh_chat:trace_route/1`** — sends a PUBLISH with a `trace_hops`
    accumulator. Each relay appends `{self_url, timestamp}`. Reply
    echoes the path back:

    ```
    alice → relay-fr-lyon → Helsinki-hub → Nuremberg-hub →
            relay-it-palermo → bob   (55 ms)
    ```

    The "memorable slide" feature.

14. **Heartbeat ticker** — bottom-of-screen ANSI status line refreshed
    every 2 s: `[alice@lisbon ▪ 3 peers ▪ 2 rooms ▪ 12ms p50]`. Cursor
    save/restore escapes.

15. **Livebook attach** — bundle a `.livemd` that `Node.connect/1`s
    over `-proto_dist macula` and runs Elixir code live. Elixir
    audience ignition.

16. **Audience participation node** — host a public `guest@demo.macula.io`
    beam with a locked-down shell. Audience SSH's in, joins a room,
    their messages appear on your screen.

## Tier 4 — bigger pieces

17. **Ring benchmark across N nodes** — classic "spawn 1 M processes,
    send token around" with message-passing timing. Native dist vs
    mesh dist.

18. **pg group demo** — `pg:join` / `pg:get_members` works cluster-wide
    via mesh. Add a room on one node, members appear on another.

19. **Split-screen TTY** — `tmux` panes: left = shell, right =
    `journalctl -f` tailing relay logs. Audience sees wire-level
    publishes as you type. Cognitive cost high, density high.

20. **Panic button** —
    `exit(whereis(macula_dist_bridge_sup), kill)`. Watch it restart,
    watch the mesh re-establish. Let-it-crash made visible.

## Single-node quartet demo — shipped

- `scripts/demo-quartet.sh` — tmux 2×2 with alice/bob/charlie/diane,
  each on a different EU relay city, auto-tour to a shared room.
- `shell.sh` takes optional relay + room → boots straight into
  `mesh_chat:tour/2`.
- `mesh_chat:prompt/1` installed automatically:
  `alice@lisbon #cars (3)>`.
- Flag emojis on chat output: `[🇵🇹 alice] Hello!`.
- `mesh_chat:roster/0` — IRC-style list with flag, city, nick per peer.
- Colored RTT in ping.

## LinkedIn Live — venue notes

- Good for reach to investors / CTOs / policy audience (BlueRock,
  Volta, Fortino are on LinkedIn). Matches the sovereignty narrative.
- Weak for technical depth — LinkedIn's chat UX is poor vs Twitch/YT.
  Autoplay demands a strong first 10-second hook.
- Best move: simulcast via Restream or StreamYard to YouTube + LinkedIn.
  YouTube captures the BEAM crowd; LinkedIn captures the business
  audience; replay sits in both feeds. Cross-post a 90-second
  highlight clip same afternoon.
- If one venue only: YouTube Live + announce on LinkedIn / Elixir
  Forum / r/elixir / HN. Technical reach 10× higher and LinkedIn
  still sees the link.

## Demo sequencing (single-node quartet)

1. `./scripts/demo-quartet.sh` — four panes light up, each connected
   to a different EU city. Audience sees geography.
2. Type `mesh_chat:say("hello from Portugal").` in alice's pane.
   Message appears in the other three, routed via real EU relays.
3. `mesh_chat:roster().` in any pane — geographic diversity visible.
4. `mesh_chat:ping(diane).` — colored RTT shows the mesh is real.
5. Kill alice: Ctrl-C twice. Charlie's presence updates.
   Relaunch `./scripts/shell.sh alice@host00.lab pt-lisbon cars` —
   she re-joins. "Auto-heal."
6. In charlie's pane:
   `rpc:call(alice, erlang, memory, []).` — Erlang dist works
   transparently over the QUIC mesh. The "magic" moment.
7. `mesh_chat:about().` — closes with the narrative card.

## Open implementation questions

- `mesh_chat:kill_relay/1` needs admin-API auth token. Stage only if
  we want the kill-demo live. Otherwise, pre-scripted via SSH+docker.
- `trace_route/1` needs a new `_chat.trace` topic protocol.
  ~80 LoC in mesh_chat + zero relay-side changes (uses existing
  PUBLISH fan-out). High value, defer until we're past the v1
  routing-plan phase.
- LinkedIn Live requires Creator Mode or Live access (may need to
  request from LinkedIn support, 3-5 day approval).

---

*See also `~/.claude/plans/PLAN_MACULA_ROUTING_V2.md` for the
architecture plan this demo showcases.*
