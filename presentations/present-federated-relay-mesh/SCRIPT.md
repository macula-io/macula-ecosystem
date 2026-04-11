# Presenter Script — Macula Federated Relay Mesh (MFRM)

## Setup (before the talk)

1. Open **macula.io** in a browser tab (landing page)
2. Open **macula.io/topology** in a second tab (interactive map)
3. Verify topology shows ~200 relays and ~10,000 nodes
4. Open two terminals for the chat demo:
   - `cd presentations/present-macula-dist && ./scripts/start-node.sh alice munich`
   - `cd presentations/present-macula-dist && ./scripts/start-node.sh bob copenhagen`
5. Verify both nodes connect and join #lobby

## Screen layout

- **Main projector**: slides (from present.sh)
- **Secondary screen**: topology map (macula.io/topology) — switch to this during demo sections

---

## Slide 1 — Title (30 sec)

"Today I want to show you infrastructure that survives anything. Not because it's expensive or hardened — but because it's designed to be disposable."

## Slide 2 — The Problem (45 sec)

"Every application you use depends on infrastructure someone else controls. AWS, Google Cloud, Azure — when they go down, you go down. And they do go down."

"Last October, a DNS race condition in AWS us-east-1 took down 141 services for 15 hours. The same month, Azure had a 50-hour outage. In June, a null-pointer crash loop took down Gmail, Docs, Drive, and Maps for 7 hours. Over 100 cloud outages in the last 12 months."

## Slide 3 — What If (30 sec)

**Switch briefly to topology map.**

"What if instead of concentrating infrastructure in a few data centers, we spread it across hundreds of lightweight relay servers?"

## Slide 4 — How It Works — MFRM (45 sec)

"The Macula Federated Relay Mesh. Three physical boxes running 200+ virtual relay identities. Each identity has its own IPv6 address, its own QUIC listener, its own city."

"Nodes connect outbound to the nearest identity. Relays peer with each other. When one dies, nodes reroute automatically."

## Slide 5 — Per-Identity IPv6 (45 sec)

"Every virtual relay has its own IPv6 address. DNS resolves directly to the identity, not the box. The node doesn't know or care which physical box it's on."

"This is what makes 200 relays on 3 boxes work. Each identity is independent."

## Slide 6 — Geographic Discovery (30 sec)

"Nodes connect to the nearest virtual relay identity by city. Munich node picks relay-de-munich. If that relay dies, it fails over to Vienna, then Zurich."

## Slide 7 — Event-Driven Presence (30 sec)

"Relays announce themselves every 60 seconds with a heartbeat. No heartbeat within 90 seconds — the relay disappears from the map. What you see on the map is what's actually alive."

## Slide 8 — Let's See It Live (2 min)

**Switch to macula.io/topology tab.**

"This is the MFRM right now. 200+ relay identities, 10,000 connected nodes."

Point out:
- Relay dots at city positions across Europe
- Peering lines between relays (Kleinberg small-world overlay)
- Node clusters around their assigned relays
- Click a relay to show detail panel
- "Total infrastructure cost: about 30 euros a month."

## Slide 9 — Now Let's Break It (2 min)

**Trigger Operation Blackout via admin API.**

Narrate:
- "Nuremberg data center goes dark. 100 relays offline."
- Watch relays disappear from the map (heartbeat TTL expires)
- "Nodes are rerouting to Helsinki and Paris..."
- "Zero downtime. Automatic."

## Slide 10 — What Just Happened (45 sec)

"The mesh lost 100+ relays. Cost: about 500 euros. Recovery: automatic, 5-7 seconds. No human needed."

## Slide 11 — The Secret (30 sec)

"Relays hold no state. They're disposable. When one dies, the node just picks another identity."

## Slide 12 — Erlang Distribution Over the Mesh (1 min)

**Switch to chat demo terminals.**

"Here's the part that blows my mind. Standard Erlang distribution — net_adm:ping, rpc:call, gen_server:call, pg groups — all work transparently over the relay mesh."

In Alice terminal:
```erlang
mesh_chat:who("lobby").        %% Shows both alice and bob
mesh_chat:say("Hello bob!").   %% Bob receives instantly
mesh_chat:ping('bob@127.0.0.1'). %% Shows RTT through relay mesh
```

"Alice is in Munich, Bob is in Copenhagen. Different relays. One Erlang cluster."

## Slide 13 — Inter-Relay Ping (30 sec)

"Virtual relays ping each other every 30 seconds. Same box: sub-millisecond. Cross-box: real QUIC round-trip. All published as mesh events for monitoring."

## Slide 14 — Message Traceroute (30 sec)

"Any message can carry an opt-in trace. Each relay appends its identity and timestamp. Full path visibility."

## Slide 15 — The Math (30 sec)

"A relay identity costs 5 euros a month. A data center costs 200 million. You can't make data centers indestructible — but you can make relays disposable."

## Slide 16 — Anyone Can Run a Relay (45 sec)

"Sign in with GitHub, enter your VPS IP and city. DNS created automatically. IPv6 assigned. Peering starts from minute one."

## Slide 17 — The Stack (30 sec)

Quick technical overview. Don't dwell.

## Slide 18 — What Can You Build (30 sec)

"Anything that needs a network."

## Slide 19 — Get Involved (30 sec)

"Run a relay. Install a node. Read the code."

## Slide 20 — Questions

---

## Timing

| Section | Duration |
|---------|----------|
| Slides 1-2 (problem) | 1.5 min |
| Slides 3-7 (MFRM architecture) | 3 min |
| Slide 8 (live topology) | 2 min |
| Slide 9 (Operation Blackout) | 2 min |
| Slides 10-11 (analysis) | 1 min |
| Slide 12 (Erlang dist demo) | 1.5 min |
| Slides 13-14 (ping + traceroute) | 1 min |
| Slides 15-19 (economics + wrap) | 2 min |
| Questions | 5+ min |

**Total: ~15 min talk + questions**
