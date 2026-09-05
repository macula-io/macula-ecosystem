# Macula Ecosystem

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-support-ea4aaa.svg?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/rgfaber)

<p align="center">
  <img src="assets/logo.svg" width="120" height="120" alt="Macula">
</p>

<p align="center">
  <strong>Documentation hub for the Macula distributed application platform</strong>
</p>

---

## What is Macula?

Macula is a **BEAM-native federated mesh platform** for building distributed applications that run across hardware operators control. The substrate provides:

- **Federated relay-mesh networking** over QUIC and HTTP/3 (no central coordinator, no proprietary cloud dependency in the data path)
- **Edge computing**: workloads run autonomously where the operator wants them
- **Content addressing and transfer**: peer-to-peer artefact distribution without external dependencies
- **Sovereign identity and authorisation**: DID identities and UCAN capability tokens
- **Application platform**: Hecate, the user-facing runtime built on Macula

## The mental model

We use a railroad-network analogy for the architectural separation between substrate, infrastructure, identity, and clients. Each role lives in a different repository and is independently operable:

| Railroad role | Macula role | Implementation |
|---|---|---|
| **The track** | Peering protocol (QUIC, mesh routing) | `macula` (the SDK and protocol) |
| **The station** | Infrastructure node (DHT participation, SWIM liveness, source-routing, bootstrap, overlay) | `macula-station` (reference implementation) |
| **The train company** | Identity-and-membership service (who is a member of which realm, capability issuance) | `macula-realm` (canonical) and `hecate-realm` (white-label or pluggable-auth variant) |
| **The passenger's ticket** | Client SDK that holds capabilities | `macula` SDK consumed by application processes |
| **The passenger** | Application process | `hecate-daemon` and similar outbound-only clients |

Stations are deliberately **realm-agnostic infrastructure**. A single station can serve multiple realms simultaneously. Realm membership is held by the realm service, not by the station. Clients (daemons) make outbound connections to a station representing their realm.

## Architecture diagram

<p align="center">
  <img src="assets/ecosystem-overview.svg" alt="Macula Ecosystem Architecture" width="100%">
</p>

> **Note.** The ecosystem-overview, mesh-architecture, and node-realm-pairing SVG diagrams currently depict the earlier hub-and-spoke model and are scheduled for regeneration to reflect the railroad model described above. Until that regeneration ships, treat the diagrams as historical reference rather than authoritative architecture.

## The Macula ecosystem

The Macula ecosystem is organised in two cooperating layers: the substrate (the `macula-io` organisation) and the application platform (the `hecate-social` organisation). Together they cover the full path from networking primitive to user-facing runtime.

### Macula: the substrate ([macula-io](https://github.com/macula-io))

Federated mesh networking and the supporting reference services that operators need to run a Macula network.

| Package | Description | Status | Links |
|---------|-------------|--------|-------|
| **macula** | Federated mesh-networking SDK and protocol over QUIC and HTTP/3. The canonical client library and the protocol specification. | Public, on hex.pm | [GitHub](https://github.com/macula-io/macula) \| [HexDocs](https://hexdocs.pm/macula) |
| **macula-station** | Reference Macula V2 station. The infrastructure node that provides DHT participation, SWIM liveness, source-routing, bootstrap, and overlay services to Macula clients. Realm-agnostic infrastructure (a single station can serve multiple realms). Renamed from `hecate-social/hecate-station` and transferred on 2026-04-30; supersedes `macula-relay`. | Public, live in production (verified 2026-09-05) | [GitHub](https://github.com/macula-io/macula-station) |
| **macula-relay** | First-generation reference relay server. Superseded by `macula-station`; kept for historical reference and for V1-network compatibility windows. | Repo currently private, archival | (private) |
| **macula-dist-relay** | Distributed-relay reference implementation used during V1 multi-relay testing. Federation-of-relays cross-routing experiments live here. | Public | [GitHub](https://github.com/macula-io/macula-dist-relay) |
| **macula-realm** | Realm mesh-membership identity service: HyParView admission, station links, realm key lifecycle. Shipped and live in production on macula.io (verified 2026-09-05); this repo builds the realm-identity half of what was a single combined service before a 2026-08-30/09-04 split -- the other half, org/app management and licensing, moved to `macula-portal`. | Repo currently private, live | (private) |
| **macula-realm-compose** | Deployment composition, renamed "Macula Portal Compose Deployment" (repo description, verified 2026-09-05) as part of the split above. | Repo currently private | (private) |
| **macula-demo** | Reference demo deployments and infrastructure scripts. | Repo currently private | (private) |
| **macula-comm-docs** | Investor and public-sector communication material (commercial pitch, federated-compute thesis articles, public-sector vertical). | Repo currently private (verified 2026-09-05) | (private) |

**Core capabilities of the substrate:**

- **DHT pub/sub**: decentralised publish/subscribe via Kademlia DHT
- **DHT RPC**: request/response patterns with service discovery (asynchronous request/response, not synchronous)
- **NAT traversal**: QUIC over UDP for firewall-friendly inbound and outbound connections
- **Capability security**: DID identities with UCAN authorisation tokens
- **Content transfer**: content-addressed storage and peer-to-peer transfer with merkle-tree verification (described below)

### Hecate: the application platform ([hecate-social](https://github.com/hecate-social))

The user-facing runtime, infrastructure, and developer tooling that turns the Macula substrate into a usable platform for operators, developers, and end users. Hecate is a separate organisation but is the canonical Macula-on-the-desktop and Macula-on-the-edge experience.

| Package | Description | Status | Links |
|---------|-------------|--------|-------|
| **hecate-realm** | ⚠ Design intent, not a built thing: a realm service variant that would ship either as a white-label of `macula-realm` or as a headless identity-capability service that allows operators to plug in any authentication and authorisation backend behind it. The repo `hecate-social/hecate-realm` (verified 2026-09-05) is actually the org's marketing website, unrelated to identity/auth -- nothing matching this description has been built under this or any other name yet. | Not built; name is taken by an unrelated repo | (n/a) |
| **hecate-daemon** | Erlang/OTP backend that runs on an operator's hardware. Outbound-only client of `macula-station`. Hosts the venture-lifecycle management, the LLM provider integrations, and the application-plugin runtime. | Public | [GitHub](https://github.com/hecate-social/hecate-daemon) |
| **hecate-web** | Native desktop user interface built with Tauri and SvelteKit. Talks to `hecate-daemon` over a Unix socket. | Public | [GitHub](https://github.com/hecate-social/hecate-web) |
| **hecate-cli** | Command-line interface. Top-level commands route to the daemon's plugins (for example, `hecate status`, `hecate install`, `hecate {plugin} {subcommand}`). | Public | [GitHub](https://github.com/hecate-social/hecate-cli) |
| **hecate-sdk** | Erlang software-development kit for building Hecate-resident applications. | Public | [GitHub](https://github.com/hecate-social/hecate-sdk) |
| **hecate-sdk-ts** | TypeScript software-development kit, used by web frontends that integrate with Hecate. | Public | [GitHub](https://github.com/hecate-social/hecate-sdk-ts) |
| **hecate-install** | Immutable edge-node operating system based on NixOS, replaces the archived `macula-os` and `macula-os-nix`. Bootstrap ISO and first-boot configuration for a fresh Hecate node. | Public | [GitHub](https://github.com/hecate-social/hecate-install) |
| **hecate-gitops** | GitOps reconciler for Hecate-managed nodes. Watches a configuration repository, reconciles podman quadlets via systemd-user, supports zero-touch deploys via container auto-update. The canonical deployment path for Hecate-based clusters. | Public | [GitHub](https://github.com/hecate-social/hecate-gitops) |
| **hecate-corpus** | Philosophy, skills, and code-generation templates that guide Hecate development. | Public | [GitHub](https://github.com/hecate-social/hecate-corpus) |

**Hecate plugin ecosystem.** Plugins live in their own `hecate-app-*` repositories under the `hecate-apps` organisation, are discovered and installed through the appstore embedded in `hecate-daemon` and `hecate-web`, and run inside `hecate-daemon`. Each plugin contributes a daemon component, optional web frontend pages, and optional CLI subcommands.

> See the dedicated [hecate-ecosystem](https://github.com/hecate-social/hecate-ecosystem) documentation hub for fuller Hecate-side detail.

### Content transfer

<p align="center">
  <img src="assets/content-transfer-flow.svg" alt="Macula Content Transfer: Want/Have/Block Protocol" width="100%">
</p>

Content transfer is a built-in capability of `macula`, not a separate component. It provides BEAM-native content-addressed storage and peer-to-peer transfer for distributing OTP releases and artefacts across the mesh without external dependencies on IPFS, BitTorrent, or comparable systems.

**Capabilities:**

- **Content-addressed storage**: Macula Content Identifiers (MCIDs) ensure that the same content has the same identifier everywhere
- **Merkle-tree verification**: chunk-level integrity verification with parallel download
- **Want/have/block protocol**: efficient peer-to-peer exchange inspired by IPFS Bitswap
- **DHT integration**: providers announce availability and consumers discover providers via the Kademlia DHT
- **Parallel download**: fetch chunks from multiple providers simultaneously
- **NAT-friendly**: uses the existing Macula QUIC transport, no additional NAT-traversal layer required

Protocol message types: `content_want`, `content_have`, `content_block`, `content_manifest_req`, `content_manifest_res`, `content_cancel`. See the [Content Transfer Guide](guides/content-transfer.md) for application-programming-interface usage and protocol details.

## Data flow

<p align="center">
  <img src="assets/data-flow.svg" alt="Event-Sourced Application Data Flow" width="100%">
</p>

## Documentation

- [**Overview**](guides/overview.md): Introduction to the ecosystem
- [**Architecture**](guides/architecture.md): How the pieces fit together
- [**Getting Started**](guides/getting-started.md): Build your first application
- [**Joining a Realm**](guides/joining-a-realm.md): Realm onboarding flow
- [**Lab Setup Scenarios**](guides/LAB_SETUP_SCENARIOS.md): Multi-node lab configurations
- [**Event Sourcing**](guides/event-sourcing.md): CQRS and event-sourcing patterns (cross-references the Reckon ecosystem)
- [**Mesh Networking**](guides/mesh-networking.md): QUIC mesh and federated-relay guide
- [**Content Transfer**](guides/content-transfer.md): Peer-to-peer artefact distribution
- [**Neuroevolution**](guides/neuroevolution.md): TWEANN and NEAT (cross-references the Faber ecosystem)
- [**MaculaOS**](guides/macula-os.md): Edge deployment (historical, superseded by `hecate-install`)

## Related ecosystems

Macula works alongside three independent ecosystems, each maintained by their own organisations.

### Reckon: Event sourcing and CQRS ([reckon-db-org](https://github.com/reckon-db-org))

A BEAM-native event-sourcing stack providing durable event stores, Command-Query Responsibility Segregation frameworks, and distributed persistence. Applications built on Macula and on Hecate use Reckon for event-sourced state management.

| Package | Description | Links |
|---------|-------------|-------|
| **reckon_db** | Distributed event store on Khepri / Ra (Raft) | [GitHub](https://github.com/reckon-db-org/reckon-db) \| [HexDocs](https://hexdocs.pm/reckon_db) |
| **evoq** | CQRS / event-sourcing framework (aggregates, commands, events) | [GitHub](https://github.com/reckon-db-org/evoq) \| [HexDocs](https://hexdocs.pm/evoq) |
| **reckon_gater** | Gateway and shared types | [GitHub](https://github.com/reckon-db-org/reckon-gater) \| [HexDocs](https://hexdocs.pm/reckon_gater) |
| **reckon_evoq** | Adapter connecting `evoq` to `reckon_db` | [GitHub](https://github.com/reckon-db-org/reckon-evoq) \| [HexDocs](https://hexdocs.pm/reckon_evoq) |

> See [reckon-ecosystem](https://github.com/reckon-db-org/reckon-ecosystem) for full Reckon-side documentation.

### Faber: Neuroevolution ([rgfaber](https://github.com/rgfaber))

Evolutionary neural-network framework for Erlang and OTP. Adaptive controllers can be evolved using TWEANN and NEAT, with optional distributed evaluation across the Macula mesh.

| Package | Description | Links |
|---------|-------------|-------|
| **faber_tweann** | TWEANN neural networks with liquid-time-constant neurons and Open Neural Network Exchange export | [GitHub](https://github.com/rgfaber/faber-tweann) \| [HexDocs](https://hexdocs.pm/faber_tweann) |
| **faber_neuroevolution** | Population-based evolutionary training with speciation and selection | [GitHub](https://github.com/rgfaber/faber-neuroevolution) \| [HexDocs](https://hexdocs.pm/faber_neuroevolution) |

> See [faber-ecosystem](https://github.com/rgfaber/faber-ecosystem) for full Faber-side documentation.

### bc_gitops: Mesh application orchestration ([beam-campus](https://github.com/beam-campus))

A complementary BEAM-native GitOps reconciler for publishing, installing, and managing Open Telecom Platform applications across a Macula mesh. Macula-based deployments use `hecate-gitops` as the canonical reconciler; `bc_gitops` is an adjacent option for operators who want a different reconciler shape or a mesh-source-type for fetching releases via Macula Content Identifiers.

| Package | Description | Links |
|---------|-------------|-------|
| **bc_gitops** | GitOps reconciler for OTP applications | [GitHub](https://github.com/beam-campus/bc-gitops) \| [HexDocs](https://hexdocs.pm/bc_gitops) |

## Why Macula?

### Reclaim your place in the AI economy

Artificial intelligence is rapidly automating cognitive work, displacing millions from traditional employment. But artificial intelligence needs compute, and that is an opportunity. Macula transforms an operator from a **displaced worker** into an **infrastructure provider**:

- **Compute as a new asset class**: operator-owned hardware becomes income-generating infrastructure
- **Run micro-datacentres**: participate in the mesh economy from a home or office
- **Own the contribution**: no middleman taking thirty percent or more of the compute value
- **Community-owned artificial intelligence**: train and run models on community infrastructure rather than on Big Tech clouds

### A platform for independents and solo developers

Big Tech platforms demand thirty-percent cuts, dictate terms, and can deplatform operators overnight. Macula puts a **production-ready distributed platform at any developer's fingertips**:

- **Zero platform fees**: keep one hundred percent of what you earn
- **No app-store gatekeepers**: deploy directly to your users
- **Built-in distribution**: applications run on the mesh and scale with demand
- **Own the relationship**: direct connection to users, no algorithm deciding distribution

### Break free from Big Tech

Five companies control most cloud infrastructure, creating vendor lock-in and data exploitation. Macula provides **infrastructure that operators own**:

- **Local data processing**: data does not leave the operator's network
- **Open standards**: no proprietary lock-in, no platform risk
- **Portable workloads**: move freely between nodes and providers

### Data sovereignty by design

Governments worldwide enforce strict data-residency requirements (the General Data Protection Regulation, the California Consumer Privacy Act, localisation laws). Macula's edge-first architecture naturally complies:

- **Processing where data is created**: no cross-border transfers
- **Cryptographic authorisation**: UCAN tokens, not central authentication servers
- **Audit trails**: event sourcing captures every state change

### Digital resilience

Centralised systems fail catastrophically. Macula's mesh architecture ensures continuity:

- **If one node fails, others continue**: no single point of failure
- **Offline-capable**: nodes operate independently when disconnected
- **Eventual consistency**: changes propagate when connectivity returns

### Environmental efficiency

Data centres consume a significant share of global electricity while operating at fifteen to twenty-five percent utilisation. Edge processing changes this:

- **Up to ten-fold energy reduction** for local processing versus cloud round-trips
- **Use existing hardware**: any device can join the mesh
- **Reduce network overhead**: process data where it is generated

### BEAM-native excellence

Every component is built on the BEAM (the Erlang virtual machine), battle-tested in telecommunications for forty years and counting:

- **Fault tolerance**: supervisors restart failed processes automatically
- **Soft real-time**: predictable latency characteristics
- **Hot code loading**: deploy without downtime
- **Massive concurrency**: millions of lightweight processes

## Use cases

- **Internet-of-Things platforms**: collect and process sensor data at the edge
- **Financial systems**: complete audit trails through event sourcing
- **Gaming**: real-time multiplayer on a mesh network
- **Robotics**: evolve controllers with [Faber](https://github.com/rgfaber/faber-ecosystem) neuroevolution
- **Healthcare**: decentralised patient data with UCAN authorisation
- **Public-sector citizen platforms**: Burgerrekengemeenschap and adjacent municipal use cases

## Community

- **Macula**: [macula-io](https://github.com/macula-io) on GitHub | search `macula` on [hex.pm](https://hex.pm)
- **Hecate**: [hecate-social](https://github.com/hecate-social) on GitHub
- **Reckon**: [reckon-db-org](https://github.com/reckon-db-org) on GitHub | search `reckon` on [hex.pm](https://hex.pm)
- **Faber**: [rgfaber](https://github.com/rgfaber) on GitHub | search `faber` on [hex.pm](https://hex.pm)
- **beam-campus**: [beam-campus](https://github.com/beam-campus) on GitHub | `bc_gitops` on [hex.pm](https://hex.pm)
- **Issues**: report bugs on the respective repositories

## License

Apache 2.0. See [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with the BEAM</sub>
</p>
