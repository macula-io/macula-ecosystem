# Lab Setup & Test Scenarios

Testing guide for Erlang/OTP clustering and Macula Mesh networking across LAN, VLAN, NAT, and WAN topologies using the BEAM lab infrastructure.

---

## Physical Topology

```
                        ┌─────────────────────┐
                        │   ISP / Internet     │
                        └──────────┬──────────┘
                                   │
                        ┌──────────┴──────────┐
                        │   Router/Modem       │
                        │   mymodem.home       │
                        │   192.168.128.1      │
                        │   MAC: 58:68:7a:..   │
                        │   Public: IPv6       │
                        │   (2a02:a03f:8b7b..) │
                        └───┬──────────────┬───┘
                            │              │
                  ┌─────────┘              └─────────┐
                  │ enp5s0                           │
     ┌────────────┴────────────┐          ┌──────────┴──────────┐
     │   Workstation (host00)  │          │   Switch            │
     │   192.168.129.3/23      │          │   (unmanaged)       │
     │   AMD Ryzen 9 5950X     │          └──┬───┬───┬───┬──────┘
     │   32 cores, 190GB RAM   │             │   │   │   │
     │   NVIDIA Quadro P2200   │             │   │   │   │
     │   Arch Linux 6.19       │             │   │   │   │
     └────────────┬────────────┘             │   │   │   │
                  │ enp4s0                   │   │   │   │
                  │ 192.168.1.100/24         │   │   │   │
                  │ (direct L2)              │   │   │   │
                  └──────────┬───────────────┘   │   │   │
                             │                   │   │   │
                   ┌─────────┴──┐  ┌─────────────┘   │   │
                   │            │  │                  │   │
              ┌────┴────┐ ┌────┴──┴─┐ ┌──────────┐ ┌─┴───┴──┐
              │ beam00  │ │ beam01  │ │ beam02   │ │ beam03  │
              │ .1.10   │ │ .1.11   │ │ .1.12    │ │ .1.13   │
              │ 16GB    │ │ 32GB    │ │ 32GB     │ │ 32GB    │
              │ 1+1 HDD │ │ 2 HDD  │ │ 2 HDD   │ │ 2 HDD   │
              │ 224G NVM│ │ 224G NVM│ │ 224G NVM │ │ 932G NVM│
              └─────────┘ └─────────┘ └──────────┘ └─────────┘
              Ubuntu 20.04, Intel Celeron J4105, Docker CE 28.1
              All headless, dual Realtek NICs (1 active, 1 spare)
```

### Additional Devices

| Device | IP | Notes |
|--------|-----|-------|
| maculaos-live | 192.168.129.14 | Laptop on router subnet |

### Network Summary

| Segment | Subnet | Gateway | Interface (host00) |
|---------|--------|---------|-------------------|
| **Router/Internet** | 192.168.128.0/23 | 192.168.128.1 | enp5s0 |
| **BEAM cluster** | 192.168.1.0/24 (configured /20) | 192.168.1.1 (= router) | enp4s0 |
| **Docker bridge** | 172.17.0.0/16 | per-node | docker0 (on each node) |

### Key Observations

- The **router** bridges both subnets (192.168.128.0/23 and 192.168.1.0/24) — same MAC on both sides
- Beam nodes use **/20 masks** (192.168.0.0-192.168.15.255) so they can see the router directly
- Workstation has **dual-homed access**: direct L2 via enp4s0, routed via enp5s0
- Each beam node has a **spare NIC** (enp2s0 or enp3s0 depending on node) currently DOWN
- **IPv6 is enabled** on all nodes with public-routable addresses (2a02:a03f:...)
- All beam nodes have **ip_forward=1**, **iptables NAT**, **VLAN (802.1q)**, and **network namespaces** available
- maculaos-live laptop is on the router subnet — a natural "remote" peer for WAN-like testing

### Capabilities Matrix

| Capability | beam00 | beam01 | beam02 | beam03 | host00 |
|-----------|--------|--------|--------|--------|--------|
| Docker CE | 28.1.1 | 28.1.1 | 28.1.1 | 28.1.1 | No |
| ip netns | sudo | sudo | sudo | sudo | sudo |
| iptables NAT | sudo | sudo | sudo | sudo | sudo |
| 802.1q VLAN | sudo | sudo | sudo | sudo | ? |
| ip_forward | 1 | 1 | 1 | 1 | ? |
| Spare NIC | enp3s0 | enp2s0 | enp2s0 | enp2s0 | wlan0 |
| IPv6 | Yes | Yes | Yes | Yes | Yes |
| Storage | /bulk0,/fast | /bulk0,1,/fast | /bulk0,1,/fast | /bulk0,1,/fast | btrfs |

---

## Scenario 1: Direct LAN (Baseline)

**Purpose:** Validate Erlang/OTP clustering and Macula mesh on a flat L2 network.

**Topology:** All nodes on 192.168.1.0/24, no barriers.

```
beam00 ──┐
beam01 ──┤── Switch ── 192.168.1.0/24 (flat L2)
beam02 ──┤
beam03 ──┘
```

**What to test:**
- Erlang `net_adm:ping/1` between all node pairs
- EPMD discovery (port 4369)
- Macula UDP multicast gossip for peer discovery
- Macula QUIC connections (port 9443)
- Pub/Sub message delivery latency
- RPC call/response round-trip
- DHT key storage and retrieval
- Content transfer (P2P artifact distribution)

**Setup:** No changes needed — this is the current default topology.

```bash
# On each beam node, start an Erlang shell:
erl -name node@beam00.lab -setcookie test_cookie

# Test connectivity:
net_adm:ping('node@beam01.lab').
```

**Expected results:**
- Sub-millisecond ping latency
- Full mesh formation in <5 seconds
- 100% message delivery
- Zero NAT traversal needed

**Value:** Establishes baseline performance numbers for comparison with constrained scenarios.

---

## Scenario 2: Routed (L3) Segmentation

**Purpose:** Test Erlang clustering and Macula mesh across different IP subnets connected by a router, without NAT.

**Topology:** Split beam nodes into two subnets using the spare NICs.

```
  Subnet A: 10.0.1.0/24                Subnet B: 10.0.2.0/24
  ┌─────────────────────┐              ┌─────────────────────┐
  │ beam00 (10.0.1.10)  │              │ beam02 (10.0.2.12)  │
  │ beam01 (10.0.1.11)  │              │ beam03 (10.0.2.13)  │
  └────────┬────────────┘              └────────┬────────────┘
           │ spare NIC                          │ spare NIC
           └──────────┐          ┌──────────────┘
                      │          │
               ┌──────┴──────────┴──────┐
               │   host00 (router)      │
               │   10.0.1.1 (enp4s0)    │
               │   10.0.2.1 (USB NIC?)  │
               │   ip_forward=1         │
               └────────────────────────┘
```

**Setup:**

The workstation has only one spare interface (enp4s0 is already used for beam access). Two options:

**Option A:** Use beam00 as the router (it has a spare NIC + ip_forward already enabled):

```
Subnet A: beam01 ──(enp3s0: 10.0.1.11)── beam00.enp3s0 (10.0.1.1)
                                              │
                                         beam00.enp2s0 (10.0.2.1)
                                              │
Subnet B: beam02 ──(enp2s0: 10.0.2.12)── beam00 routes ── beam03 (10.0.2.13)
```

**Option B:** Use Docker networks on different nodes (no hardware changes):

```bash
# On beam01: create isolated network
sudo docker network create --subnet=10.0.1.0/24 subnet-a

# On beam03: create isolated network
sudo docker network create --subnet=10.0.2.0/24 subnet-b

# Run Macula nodes inside containers on these networks
# Add static routes on the switch so 10.0.1.0/24 routes via beam01
# and 10.0.2.0/24 routes via beam03
```

**What to test:**
- Erlang clustering across subnets (requires explicit node naming, not mDNS)
- Macula bootstrap-based discovery (can't use multicast across subnets)
- QUIC connection establishment over routed path
- DHT query escalation when peers are on different subnets

**Expected results:**
- Erlang clustering works if nodes are explicitly configured (no automatic discovery via multicast)
- Macula needs bootstrap nodes or explicit peer addresses
- Slightly higher latency (routing overhead)
- No NAT issues — just routing

---

## Scenario 3: VLAN Isolation (802.1q)

**Purpose:** Test mesh behavior with VLAN-tagged traffic, simulating enterprise network segmentation.

**Topology:** Create VLANs on the beam nodes' active NICs.

```
  Physical: 192.168.1.0/24 (untagged)
  ┌──────────────────────────────────────┐
  │           Switch (unmanaged)         │
  └──┬──────┬──────┬──────┬─────────────┘
     │      │      │      │
   beam00 beam01 beam02 beam03

  Logical VLANs (software-defined on each node):
  VLAN 10: beam00 (10.10.10.10) + beam01 (10.10.10.11)
  VLAN 20: beam02 (10.10.20.12) + beam03 (10.10.20.13)
  VLAN 30: beam00 (10.10.30.10) + beam03 (10.10.30.13)   ← cross-VLAN pair
```

**NOTE:** The switch is unmanaged, so 802.1q tagged frames pass through transparently. VLAN isolation is enforced by the Linux kernel on each node — only nodes with the same VLAN ID configured will process each other's tagged frames.

**Setup:**

```bash
# On beam00: join VLAN 10 and VLAN 30
sudo ip link add link enp2s0 name enp2s0.10 type vlan id 10
sudo ip addr add 10.10.10.10/24 dev enp2s0.10
sudo ip link set enp2s0.10 up

sudo ip link add link enp2s0 name enp2s0.30 type vlan id 30
sudo ip addr add 10.10.30.10/24 dev enp2s0.30
sudo ip link set enp2s0.30 up

# On beam01: join VLAN 10
sudo ip link add link enp3s0 name enp3s0.10 type vlan id 10
sudo ip addr add 10.10.10.11/24 dev enp3s0.10
sudo ip link set enp3s0.10 up

# On beam02: join VLAN 20
sudo ip link add link enp3s0 name enp3s0.20 type vlan id 20
sudo ip addr add 10.10.20.12/24 dev enp3s0.20
sudo ip link set enp3s0.20 up

# On beam03: join VLAN 20 and VLAN 30
sudo ip link add link enp3s0 name enp3s0.20 type vlan id 20
sudo ip addr add 10.10.20.13/24 dev enp3s0.20
sudo ip link set enp3s0.20 up

sudo ip link add link enp3s0 name enp3s0.30 type vlan id 30
sudo ip addr add 10.10.30.13/24 dev enp3s0.30
sudo ip link set enp3s0.30 up
```

**What to test:**
- Nodes on the same VLAN can discover each other (multicast within VLAN)
- Nodes on different VLANs cannot communicate without a router
- Macula realm isolation: VLAN 10 = realm "alpha", VLAN 20 = realm "beta"
- Cross-VLAN node (beam00 on VLAN 10+30, beam03 on VLAN 20+30) acts as a bridge
- DHT bridge behavior when a node spans multiple VLANs

**Expected results:**
- Clean isolation between VLANs — no cross-talk
- Multicast discovery confined to VLAN boundaries
- Bridge node can relay messages between realms via VLAN 30

---

## Scenario 4: NAT Traversal (Simulated)

**Purpose:** Test Macula's NAT hole-punching and relay fallback with realistic NAT types.

**Topology:** Use two beam nodes as NAT routers, isolating the other two.

```
              "Public" side: 192.168.1.0/24
              ┌──────────────────────────────┐
              │           Switch             │
              └──┬────────────────────────┬──┘
                 │                        │
            beam00 (router A)        beam02 (router B)
            pub: 192.168.1.10        pub: 192.168.1.12
            priv: 10.0.1.1           priv: 10.0.2.1
            NAT (iptables)           NAT (iptables)
                 │ (veth pair)            │ (veth pair)
                 │                        │
            beam01 (behind NAT A)    beam03 (behind NAT B)
            10.0.1.2                 10.0.2.2
            (netns: nat-a)           (netns: nat-b)
```

beam01 and beam03 are isolated in network namespaces with NAT. They cannot talk to each other directly — packets must go through NAT on beam00/beam02.

**Setup (on beam00 — router A):**

```bash
# Create namespace for beam01's "private" side
sudo ip netns add nat-a
sudo ip link add veth-pub type veth peer name veth-priv
sudo ip link set veth-priv netns nat-a

# Public side (beam00)
sudo ip addr add 10.0.1.1/24 dev veth-pub
sudo ip link set veth-pub up

# Private side (inside namespace)
sudo ip netns exec nat-a ip addr add 10.0.1.2/24 dev veth-priv
sudo ip netns exec nat-a ip link set veth-priv up
sudo ip netns exec nat-a ip link set lo up
sudo ip netns exec nat-a ip route add default via 10.0.1.1

# Enable NAT
sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -o enp2s0 -j MASQUERADE
sudo iptables -A FORWARD -i veth-pub -o enp2s0 -j ACCEPT
sudo iptables -A FORWARD -i enp2s0 -o veth-pub -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Repeat symmetrically on beam02 for beam03 (namespace `nat-b`, subnet `10.0.2.0/24`).

**NAT Type Variations:**

```bash
# Full Cone NAT (most permissive)
sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE

# Address-Restricted Cone
sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE
sudo iptables -A FORWARD -i enp2s0 -o veth-pub \
  -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i enp2s0 -o veth-pub \
  -m state --state NEW -j DROP

# Port-Restricted Cone (default Linux behavior with conntrack)
# Same as address-restricted — Linux conntrack is port-aware by default

# Symmetric NAT (hardest to traverse)
sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE --random
```

**Running Macula in the namespace:**

```bash
# Start a Macula node inside the NATted namespace
sudo ip netns exec nat-a su - rl -c '
  cd /path/to/macula
  ERL_FLAGS="-name node@10.0.1.2" rebar3 shell
'
```

**What to test:**

| NAT A ↔ NAT B | Expected Result |
|----------------|-----------------|
| Full Cone ↔ Full Cone | Direct P2P via hole-punch |
| Full Cone ↔ Port-Restricted | P2P possible (A initiates) |
| Port-Restricted ↔ Port-Restricted | P2P via simultaneous open |
| Symmetric ↔ Full Cone | P2P possible (prediction) |
| Symmetric ↔ Symmetric | **Must fall back to relay** |

**Key metrics:**
- Hole-punch success rate per NAT combination
- Time to establish P2P connection
- Relay fallback detection time
- Throughput difference: direct vs relayed

---

## Scenario 5: WAN Simulation

**Purpose:** Test Macula mesh behavior with realistic WAN conditions (latency, packet loss, bandwidth limits).

**Topology:** Use `tc` (traffic control) to add WAN-like impairments between nodes.

```
beam00 ←──── 50ms latency, 1% loss ────→ beam02
beam01 ←──── 150ms latency, 5% loss ───→ beam03
```

**Setup:**

```bash
# On beam00: add 50ms latency + 1% loss to traffic toward beam02
sudo tc qdisc add dev enp2s0 root handle 1: prio
sudo tc qdisc add dev enp2s0 parent 1:3 handle 30: netem \
  delay 50ms 10ms distribution normal loss 1%
sudo tc filter add dev enp2s0 protocol ip parent 1:0 prio 3 \
  u32 match ip dst 192.168.1.12/32 flowid 1:3

# On beam01: add 150ms latency + 5% loss to traffic toward beam03
sudo tc qdisc add dev enp3s0 root handle 1: prio
sudo tc qdisc add dev enp3s0 parent 1:3 handle 30: netem \
  delay 150ms 30ms distribution normal loss 5%
sudo tc filter add dev enp3s0 protocol ip parent 1:0 prio 3 \
  u32 match ip dst 192.168.1.13/32 flowid 1:3

# Bandwidth limit (1 Mbps to simulate poor connections)
sudo tc qdisc add dev enp3s0 parent 30:1 handle 40: tbf \
  rate 1mbit burst 32kbit latency 400ms
```

**Cleanup:**

```bash
sudo tc qdisc del dev enp2s0 root
sudo tc qdisc del dev enp3s0 root
```

**What to test:**
- QUIC connection establishment under latency
- Pub/Sub message ordering with packet loss
- DHT consistency with high-latency peers
- Content transfer throughput with bandwidth limits
- CRDT convergence time under loss
- Kademlia routing table stability with flapping peers
- Macula's adaptive NAT timing under varying RTT

**WAN profiles to simulate:**

| Profile | Latency | Jitter | Loss | Bandwidth | Simulates |
|---------|---------|--------|------|-----------|-----------|
| LAN | 0ms | 0ms | 0% | 1 Gbps | Baseline |
| City | 5ms | 2ms | 0.1% | 100 Mbps | Same-city datacenter |
| Regional | 30ms | 10ms | 0.5% | 50 Mbps | Same-country |
| Continental | 80ms | 20ms | 1% | 20 Mbps | Cross-country |
| Intercontinental | 150ms | 40ms | 2% | 10 Mbps | Cross-ocean |
| Edge/Mobile | 100ms | 50ms | 5% | 2 Mbps | Mobile/satellite |
| Hostile | 200ms | 100ms | 10% | 512 Kbps | War zone |

---

## Scenario 6: Split-Brain and Partition

**Purpose:** Test Erlang cluster and Macula mesh behavior during network partitions.

**Topology:** Use iptables to create and heal partitions.

```
  Partition A              │ BLOCKED │           Partition B
  beam00 ←→ beam01         │ iptables│           beam02 ←→ beam03
                            │  DROP   │
```

**Setup:**

```bash
# On beam00 and beam01: block traffic to beam02 and beam03
sudo iptables -A INPUT -s 192.168.1.12 -j DROP
sudo iptables -A INPUT -s 192.168.1.13 -j DROP
sudo iptables -A OUTPUT -d 192.168.1.12 -j DROP
sudo iptables -A OUTPUT -d 192.168.1.13 -j DROP

# (same rules on beam02/beam03 blocking beam00/beam01)

# Heal partition (remove rules):
sudo iptables -D INPUT -s 192.168.1.12 -j DROP
# ... etc
```

**What to test:**
- Erlang `net_kernel` split-brain detection and healing
- CRDT convergence after partition heals (LWW-Register, OR-Set conflicts)
- Macula DHT repair (re-replication of keys)
- Pub/Sub message queue behavior during partition
- Event store consistency (ReckonDB Raft consensus with minority partition)
- Time to full mesh restoration after healing

**Partition patterns:**

| Pattern | Description | Tests |
|---------|-------------|-------|
| Clean split | 2+2 partition | Raft leader election, CRDT divergence |
| Asymmetric | 3+1 isolation | Minority node behavior, rejoin |
| Flapping | Partition on/off every 30s | Stability under instability |
| Progressive | Remove nodes one by one | Graceful degradation |
| Total isolation | All 4 nodes isolated | Full recovery from zero |

---

## Scenario 7: Real WAN via Internet

**Purpose:** Test actual WAN connectivity using your public IPv6 and the Macula bootstrap infrastructure.

**Topology:**

```
  Your LAN (beam cluster)          Internet         Remote
  ┌──────────────────┐                              ┌──────────────┐
  │ beam00-03        │ ←── IPv6 / QUIC ──────────→  │ macula.io    │
  │ 2a02:a03f:...    │     (real WAN path)          │ (bootstrap)  │
  └──────────────────┘                              └──────────────┘
                                                    ┌──────────────┐
  ┌──────────────────┐                              │ VPS / friend │
  │ maculaos-live    │ ←── IPv6 / QUIC ──────────→  │ (optional)   │
  │ 192.168.129.14   │                              └──────────────┘
  └──────────────────┘
```

**What to test:**
- Bootstrap connection to `boot.macula.io:443`
- Realm join over real internet
- Pub/Sub between beam cluster and remote nodes
- NAT traversal from behind your ISP router (likely Carrier-Grade NAT for IPv4)
- IPv6-native QUIC connections (no NAT at all on IPv6)
- Content transfer over WAN (throughput, integrity)

**Available assets:**
- **macula.io** — production Linode server (accessible via `sshpass -f ~/.config/macula/sshpass.txt ssh root@macula.io`)
- **maculaos-live** (192.168.129.14) — laptop on the router subnet, can simulate a "remote" peer if connected via WiFi through a different router
- **IPv6** — all nodes have public IPv6 addresses, so true end-to-end connectivity without NAT

---

## Scenario 8: Docker Network Isolation

**Purpose:** Quick NAT/isolation tests using Docker's built-in networking — no namespace setup required.

**Topology:**

```
  beam01: docker network "realm-alpha" (172.20.0.0/24)
    └── container: macula-alpha (172.20.0.2)
                        │
                   host network (192.168.1.11)
                        │
  beam03: docker network "realm-beta" (172.21.0.0/24)
    └── container: macula-beta (172.21.0.2)
```

**Setup:**

```bash
# On beam01
sudo docker network create --subnet=172.20.0.0/24 realm-alpha
sudo docker run -d --name macula-alpha \
  --network realm-alpha \
  ghcr.io/macula-io/macula:latest

# On beam03
sudo docker network create --subnet=172.21.0.0/24 realm-beta
sudo docker run -d --name macula-beta \
  --network realm-beta \
  ghcr.io/macula-io/macula:latest
```

Docker's bridge networking applies NAT (MASQUERADE) automatically. Containers on different Docker networks on different hosts experience real NAT — they cannot talk directly without port mapping or host networking.

**What to test:**
- Container-to-container connectivity through Docker NAT
- Macula bootstrap discovery from inside a container
- Port-mapped QUIC (mapping host port to container)
- Comparison: `--network host` vs bridge vs custom

---

## Quick Reference: Setup/Teardown Scripts

All scenario scripts should be placed in `~/scripts/lab/` on the workstation and deployed via SSH.

| Script | Purpose |
|--------|---------|
| `lab-vlan-setup.sh` | Create VLAN interfaces on beam nodes |
| `lab-vlan-teardown.sh` | Remove VLAN interfaces |
| `lab-nat-setup.sh` | Create NAT namespaces (scenario 4) |
| `lab-nat-teardown.sh` | Destroy NAT namespaces |
| `lab-wan-sim.sh <profile>` | Apply tc WAN impairments |
| `lab-wan-clear.sh` | Remove tc rules |
| `lab-partition.sh <pattern>` | Create iptables partitions |
| `lab-partition-heal.sh` | Remove all iptables DROP rules |
| `lab-status.sh` | Report current lab state across all nodes |

---

## Recommended Test Order

1. **Scenario 1** (Direct LAN) — establish baseline metrics
2. **Scenario 5** (WAN Simulation) — validate QUIC resilience under impairment
3. **Scenario 6** (Split-Brain) — validate Raft consensus and CRDT convergence
4. **Scenario 3** (VLAN) — validate realm isolation via network segmentation
5. **Scenario 4** (NAT Traversal) — validate hole-punching across all NAT types
6. **Scenario 8** (Docker Networks) — quick NAT tests without namespace complexity
7. **Scenario 2** (Routed L3) — validate cross-subnet bootstrap discovery
8. **Scenario 7** (Real WAN) — end-to-end validation over the internet
