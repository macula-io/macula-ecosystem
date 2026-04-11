# Presentation Script: Erlang Distribution Through a Relay Mesh

**Duration:** 5-7 minutes
**Audience:** BEAM developers (Erlang/Elixir)
**Format:** Live demo with slides (or screen recording with voiceover)

---

## Setup

1. Clone and build:
   ```bash
   cd macula-demo/presentations/present-macula-dist
   rm -f rebar.lock && rebar3 compile
   ```

2. Two terminals open side-by-side

3. Slides open in browser:
   ```bash
   cd presentation
   npx @marp-team/marp-cli SLIDES.md -o slides.html --allow-local-files
   open slides.html
   ```

---

## Script

### [0:00-0:30] SLIDES 1-2 — The Problem

> "Erlang distribution is one of the most powerful features of the BEAM.
> net_adm:ping, gen_server:call, pg:join — all work transparently across nodes.
>
> But it has one hard requirement: both nodes must reach each other directly.
> Behind NATs, firewalls, across cloud providers? It breaks.
>
> What if nodes only needed OUTBOUND connectivity?"

### [0:30-1:00] SLIDES 3-5 — The Architecture

> "Each node connects outbound to a relay over QUIC. The relay just forwards bytes.
>
> Inside each node, a gen_tcp loopback socket pair: one end goes to OTP's dist_util —
> it gets a real file descriptor — the other end bridges to the relay via pub/sub.
>
> The bridge uses packet raw — transparent byte pipe. When dist_util switches from
> packet 2 during handshake to packet 4, the bridge doesn't care."

### [1:00-1:30] SLIDE 6 — The Bugs

> "Five bugs, each silent. The worst: setting kernel_pid to self() in the spawned
> process instead of net_kernel. Permanent deadlock. No error. Just silence."

### [1:30-2:00] SLIDE 7 — Live Demo Setup

> "Let me show you this live. Two terminals. Alice connects to the Nuremberg relay
> in Germany. Bob connects to Helsinki in Finland. Different relays, different countries.
> Neither can reach the other directly."

### [2:00-3:00] SLIDES 8-9 — Alice and Bob Join (LIVE)

*Terminal 1 (LEFT):*
```
$ MACULA_DIST_MODE=relay ERL_FLAGS="-proto_dist macula -no_epmd" rebar3 shell --name alice@127.0.0.1 --setcookie DEMO
1> mesh_chat:connect("relay-cz-prague.macula.io").
```

*Wait for "Connected!" and "Ready!"*

*Terminal 2 (RIGHT):*
```
$ MACULA_DIST_MODE=relay ERL_FLAGS="-proto_dist macula -no_epmd" rebar3 shell --name bob@127.0.0.1 --setcookie DEMO
1> mesh_chat:connect("relay-dk-copenhagen.macula.io").
```

*Wait for "Connected!" and "Ready!"*

> "Both connected. Now let's see if they can find each other."

*Terminal 2:*
```
2> net_adm:ping('alice@127.0.0.1').
pong
```

> "Pong! Full OTP distribution handshake through two relays and a DHT lookup."

### [3:00-4:00] SLIDE 10 — Chat! (LIVE)

*Terminal 1:*
```
2> mesh_chat:say("Hello from Germany!").
```

*Both terminals show the message*

*Terminal 2:*
```
3> mesh_chat:say("Hei from Finland!").
```

*Both terminals show it*

> "Standard Erlang message passing. Through two relays. Encrypted."

*Terminal 2:*
```
4> mesh_chat:whisper('alice@127.0.0.1', "This is just for you").
```

> "Direct message. gen_server:call under the hood. Cross-border, through the mesh."

*Terminal 1:*
```
3> mesh_chat:peers().
```

> "One peer connected. Bob in Finland."

### [4:00-4:30] SLIDE 11 — Sequence Diagram

> "Here's what happened. Alice's relay found Bob's relay via Kademlia DHT.
> Tunnel created. dist_util handshake. AES-256-GCM encrypted — the relay
> only sees ciphertext. After that, standard OTP distribution."

### [4:30-5:00] SLIDES 12-13 — Everything Works + The Code

> "Everything you'd expect works. gen_server:call, pg groups, monitors, rpc:call.
> The nodes believe they have a TCP connection. The tunnel handles everything.
>
> Three lines to enable in your app. Published on hex.pm as macula v1.0."

### [5:00-5:30] SLIDES 14-15 — What's Next + Close

> "303 relays across 35 European countries. 10,000 nodes on the mesh today.
> Multi-relay failover, RTT-based selection, and E2E encryption coming next.
>
> Erlang distribution doesn't need direct connectivity anymore. Outbound QUIC
> to a relay. That's all. Thank you."

---

## Demo Recovery

If the live demo fails:
- Check relay status: `curl https://relay-cz-prague.macula.io:4433/health`
- Fall back to same relay: both use nuremberg (avoids cross-relay DHT)
- Have a screen recording of a successful run as backup

## After the Demo

```
%% In both terminals:
mesh_chat:leave().
q().
```
