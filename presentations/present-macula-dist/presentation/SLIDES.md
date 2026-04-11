---
marp: true
theme: uncover
class: invert
paginate: true
style: |
  section {
    font-size: 22px;
    line-height: 1.5;
  }
  h1 { font-size: 36px; }
  h2 { font-size: 28px; }
  code { font-size: 18px; }
  pre { font-size: 16px; line-height: 1.4; }
  table { font-size: 16px; }
  img { background: transparent; }
  .columns { display: flex; gap: 2em; }
  .columns > * { flex: 1; }
---

<!-- Render: npx @marp-team/marp-cli SLIDES.md -o slides.html --allow-local-files -->

# Erlang Distribution
# Through the Macula Relay Mesh

**net_adm:ping across firewalls, NATs, and continents**

macula v1.4 — April 2026

![width:100px](assets/logo.svg)

---

## The Problem

Erlang distribution assumes **mutual reachability**.

```
Node A ◄──── TCP (port 4369+) ────► Node B
```

Behind NATs, firewalls, across cloud providers, on edge devices?

**It doesn't work.** Both sides need open ports and routable IPs.

What if nodes only needed **outbound** connectivity?

---

## The Solution: MFRM

**Macula Federated Relay Mesh** — stateless QUIC routers.

![width:700px](assets/connect_flow.svg)

Both nodes connect **out** to a relay over QUIC.
No inbound ports. No VPNs. No tunnels to manage.

---

## How It Works: gen_tcp Loopback Bridge

![width:700px](assets/dist_over_mesh.svg)

---

## The Trick: Packet Framing

<div class="columns">
<div>

**Handshake phase:**
`{packet, 2}` — 2-byte length prefix

**Post-handshake:**
`{packet, 4}` — 4-byte length prefix

**Bridge socket:**
`{packet, raw}` — doesn't care!

Forwards raw bytes including headers.
Framing is dist_util's job, not ours.

</div>
<div>

```
dist_util (OTP)
    │
DistSock {packet, 2→4}
    │ loopback pair
BridgeSock {packet, raw}
    │
reader ──► relay pub/sub
writer ◄── relay pub/sub
```

OTP gets a **real file descriptor**.
The bridge is a transparent byte pipe.

</div>
</div>

---

## 5 Bugs That Taught Me OTP Internals

| # | Bug | Lesson |
|---|-----|--------|
| 1 | `binary_to_list` | dist_util matches `[$N \| _]` — expects charlists |
| 2 | `getstat` return | Must return `{ok, R, W, P}` 4-tuple, not `{ok, proplist}` |
| 3 | `kernel_pid = self()` | Must be net_kernel PID — deadlocks otherwise |
| 4 | `{packet,2}` on bridge | Bridge can't decode when dist switches to `{packet,4}` |
| 5 | gen_tcp vs QUIC | QUIC needs `handoff_done`; gen_tcp doesn't |

Each one: silent failure, no error message, hours of debugging.

---

## Live Demo: Interactive Mesh Chat

Four terminals. Four relays. Four countries. One mesh.

```
Terminal 1 (Alice)    Terminal 2 (Bob)     Terminal 3 (Chris)   Terminal 4 (Diana)
──────────────────    ─────────────────    ──────────────────   ──────────────────
relay-cz-prague      relay-dk-copenhagen  relay-nl-amsterdam   relay-de-munich
    (Czech Republic)         (Denmark)        (Netherlands)         (Germany)
```

No node can reach any other directly.
All connect **outbound** to their nearest virtual relay identity.

---

<!-- _class: "" -->

## Demo: Alice Joins (Terminal 1)

```erlang
$ MACULA_DIST_MODE=relay ERL_FLAGS="-proto_dist macula -no_epmd" \
  rebar3 shell --name alice@127.0.0.1 --setcookie DEMO

1> mesh_chat:connect("relay-cz-prague.macula.io").
[chat] Connecting to relay-cz-prague.macula.io...
[chat] Connected! Node: 'alice@127.0.0.1'
ok

2> mesh_chat:join("lobby").
[chat] Joined #lobby
```

Alice connected to Prague relay via QUIC over IPv6. Joined the lobby.

---

<!-- _class: "" -->

## Demo: Bob Joins (Terminal 2)

```erlang
$ MACULA_DIST_MODE=relay ERL_FLAGS="-proto_dist macula -no_epmd" \
  rebar3 shell --name bob@127.0.0.1 --setcookie DEMO

1> mesh_chat:connect("relay-dk-copenhagen.macula.io").
[chat] Connecting to relay-dk-copenhagen.macula.io...
[chat] Connected! Node: 'bob@127.0.0.1'
ok

2> mesh_chat:join("lobby").
[chat] Joined #lobby

3> net_adm:ping('alice@127.0.0.1').
pong
```

Bob connects to Copenhagen. Pings Alice through the mesh. **pong.**

---

<!-- _class: "" -->

## Demo: Chris Joins (Terminal 3)

```erlang
$ MACULA_DIST_MODE=relay ERL_FLAGS="-proto_dist macula -no_epmd" \
  rebar3 shell --name chris@127.0.0.1 --setcookie DEMO

1> mesh_chat:connect("relay-nl-amsterdam.macula.io").
[chat] Connected! Node: 'chris@127.0.0.1'

2> mesh_chat:join("lobby").
[chat] Joined #lobby

3> mesh_chat:who("lobby").
[chat] #lobby — 3 member(s):
  ● alice
  ● bob
  ● chris
```

Three nodes, three relays, three countries. One lobby.

---

<!-- _class: "" -->

## Demo: Diana Joins (Terminal 4)

```erlang
$ MACULA_DIST_MODE=relay ERL_FLAGS="-proto_dist macula -no_epmd" \
  rebar3 shell --name diana@127.0.0.1 --setcookie DEMO

1> mesh_chat:connect("relay-de-munich.macula.io").
[chat] Connected! Node: 'diana@127.0.0.1'

2> mesh_chat:join("lobby").
[chat] Joined #lobby

3> mesh_chat:join("german").
[chat] Joined #german

4> mesh_chat:rooms().
[chat] 2 room(s):
  # german (1 member)
  # lobby (4 members)
```

Diana is in two rooms. Four nodes across four relays.

---

<!-- _class: "" -->

## Demo: Ping!

```erlang
%% Alice pings Diana (Prague → Munich — different relays):
4> mesh_chat:ping('diana@127.0.0.1').
[ping] Pinging diana...

  ● alice  via relay-cz-prague.macula.io
  │ ↕ QUIC tunnel (TLS 1.3)
  │ ↕ relay mesh peering
  │ ↕ QUIC tunnel (TLS 1.3)
  ● diana  via relay-de-munich.macula.io

  RTT: 23.4ms  (Erlang RPC over QUIC relay mesh)

%% Bob pings Alice (Copenhagen → Prague):
4> mesh_chat:ping('alice@127.0.0.1').

  ● bob    via relay-dk-copenhagen.macula.io
  │ ↕ QUIC tunnel (TLS 1.3)
  │ ↕ relay mesh peering
  │ ↕ QUIC tunnel (TLS 1.3)
  ● alice  via relay-cz-prague.macula.io

  RTT: 18.7ms
```

---

<!-- _class: "" -->

## Demo: Chat!

```erlang
%% Alice says hello — all 4 terminals see it:
3> mesh_chat:say("lobby", "Hello from Prague!").
[alice/#lobby] Hello from Prague!

%% Chris replies from Amsterdam:
5> mesh_chat:say("lobby", "Hallo from Amsterdam!").
[chris/#lobby] Hallo from Amsterdam!

%% Diana whispers to Chris (only Chris sees it):
5> mesh_chat:whisper('chris@127.0.0.1', "Pssst, Biergarten?").
[diana → chris] Pssst, Biergarten?

%% Diana says something in the german room:
6> mesh_chat:say("german", "Ist jemand hier?").
[diana/#german] Ist jemand hier?

%% Chris joins german too:
6> mesh_chat:join("german").
7> mesh_chat:say("german", "Ja, ik ben er!").
[chris/#german] Ja, ik ben er!
```

---

## What Just Happened

```
Alice               Relay (Prague)       Relay (Copenhagen)        Bob
  │                      │                     │                    │
  ├─ QUIC connect ──────►│                     │◄──── QUIC ────────┤
  │                      │◄═══ mesh peering ══►│                    │
  │                      │                     │                    │
  ├─ RPC: tunnel ───────►├─── DHT lookup ─────►├── tunnel req ────►│
  │◄─ tunnel_id ─────────┤◄────────────────────┤◄── tunnel ack ────┤
  │                      │                     │                    │
  ├── dist handshake ───►├────────────────────►├──────────────────►│
  │◄── dist handshake ───┤◄────────────────────┤◄──────────────────┤
  │                      │                     │                    │
  │◄══════════ OTP Distribution Connected ═════════════════════════►│
  │                      │                     │                    │
  ├── pg:join / say() ──►├────────────────────►├── message ───────►│
```

Standard OTP distribution. AES-256-GCM encrypted. Relay sees only ciphertext.

---

## Everything Works

```erlang
net_adm:ping('bob@127.0.0.1').            %% → pong
gen_server:call({Name, 'bob@...'}, Req).   %% works
Pid ! Message.                             %% works
pg:join(pg, Group, self()).                %% works
monitor(process, {Name, 'bob@...'}).       %% works
rpc:call('bob@...', Module, Fun, Args).    %% works
```

Tick keepalive flows through the bridge. 0 errors after 72h soak test.
Tunnel encrypted with AES-256-GCM — key derived from distribution cookie.

---

## The Code

<div class="columns">
<div>

**macula SDK** (hex.pm/macula)
- `macula_dist.erl` — carrier interface (533 lines)
- `macula_dist_bridge.erl` — relay bridge (252 lines)
- `macula_dist_relay.erl` — tunnel setup
- 39 tests

</div>
<div>

**3 lines to enable:**

```erlang
macula:join_mesh(#{
    relays => [<<"https://...">>],
    realm => <<"io.macula">>
}).
%% That's it. net_adm:ping works now.
```

Or use `mesh_chat:connect/1` for the demo.

</div>
</div>

---

## What's Next

- **Multi-relay failover** — node connected to N relays simultaneously
- **RTT-based relay selection** — nearest relay via geographic + ping measurement
- **Store-and-forward** — offline nodes catch up via event replay
- **E2EE tunnels** — endpoint encryption beyond the relay layer

The MFRM has 200+ virtual relay identities across 30+ European countries,
10,000 stub nodes, and 3 physical relay boxes — ~30 EUR/month total.

---

## Thank You

**Erlang distribution doesn't need direct connectivity anymore.**

Outbound QUIC to a relay. That's all.

<div class="columns">
<div>

**Code:** github.com/macula-io/macula
**Package:** hex.pm/packages/macula
**Ecosystem:** github.com/macula-io/macula-ecosystem

</div>
<div>

![width:120px](assets/logo.svg)

(c) 2020-2026 BEAM Campus
Apache-2.0

</div>
</div>
