# Macula Ecosystem

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://buymeacoffee.com/beamologist)

<p align="center">
  <img src="assets/logo.svg" width="120" height="120" alt="Macula">
</p>

<p align="center">
  <strong>Documentation hub for the Macula distributed application platform</strong>
</p>

---

## What is Macula?

Macula is a **BEAM-native platform** for building distributed, event-sourced applications that run on a decentralized mesh network. The ecosystem combines:

- **Event Sourcing** - Capture every state change as an immutable event
- **Mesh Networking** - HTTP/3 over QUIC for NAT-friendly communication
- **Edge Computing** - Run workloads autonomously at the edge
- **Neuroevolution** - Evolve adaptive neural network controllers

## Architecture Overview

<p align="center">
  <img src="assets/ecosystem-overview.svg" alt="Macula Ecosystem Architecture" width="100%">
</p>

## Mesh Architecture

<p align="center">
  <img src="assets/mesh-architecture.svg" alt="Macula Mesh: Decentralized Service Architecture" width="100%">
</p>

Edge nodes form clusters that participate in a realm (mesh). Services advertise to the Kademlia DHT, consumers discover them, and communication happens via RPC (request/response) or PubSub (broadcast). All interactions are secured with DID identities and UCAN capability tokens.

## The Ecosystem

The platform comprises three distinct pillars, each addressing a core need:

---

### Macula Mesh — Decentralized Infrastructure

A BEAM-native HTTP/3 mesh network for edge computing.

| Package | Description | Links |
|---------|-------------|-------|
| **macula** | HTTP/3 mesh networking over QUIC with DHT-based service discovery | [GitHub](https://github.com/macula-io/macula) \| [HexDocs](https://hexdocs.pm/macula) |
| **macula_console** | Management console for Macula nodes and clusters | [GitHub](https://github.com/macula-io/macula-console) |
| **macula_os** | Immutable edge node operating system (based on k3os) | [GitHub](https://github.com/macula-io/macula-os) |

**Core capabilities:**
- **DHT PubSub** — Decentralized publish/subscribe via Kademlia DHT
- **DHT RPC** — Request/response patterns with service discovery
- **NAT Traversal** — HTTP/3 over QUIC for firewall-friendly communication
- **Capability Security** — DID identities with UCAN authorization tokens

---

### bc_gitops — Mesh Application Orchestration ([beam-campus](https://github.com/beam-campus))

BEAM-native GitOps reconciler for publishing, installing, and managing OTP applications across the mesh.

| Package | Description | Links |
|---------|-------------|-------|
| **bc_gitops** | GitOps reconciler for OTP applications | [GitHub](https://github.com/beam-campus/bc-gitops) \| [HexDocs](https://hexdocs.pm/bc_gitops) |

**Core capabilities:**
- **GitOps Reconciliation** — Watches a Git repository for application specifications
- **Auto-deployment** — Automatically deploys, upgrades, and removes applications based on config changes
- **Hot Code Reload** — Supports hot code upgrades for same-version changes
- **Dependency Management** — Respects application dependencies during deployment
- **Multi-format Config** — Supports Erlang terms, YAML, and JSON config files
- **Pluggable Runtime** — Custom deployment strategies via runtime behaviour

---

### Macula Machine Learning — Neuroevolution Framework

Evolve adaptive neural network controllers using TWEANN and NEAT.

| Package | Description | Links |
|---------|-------------|-------|
| **macula_tweann** | Topology & Weight Evolving Artificial Neural Networks | [GitHub](https://github.com/macula-io/macula-tweann) \| [HexDocs](https://hexdocs.pm/macula_tweann) |
| **macula_neuroevolution** | Full neuroevolution framework with populations and species | [GitHub](https://github.com/macula-io/macula-neuroevolution) \| [HexDocs](https://hexdocs.pm/macula_neuroevolution) |

**Core capabilities:**
- **NEAT Algorithm** — NeuroEvolution of Augmenting Topologies
- **Distributed Evaluation** — Evolve populations across mesh nodes
- **Speciation** — Protect innovation through species-based selection
- **Real-time Adaptation** — Evolve controllers for dynamic environments

---

### Reckon Ecosystem — Event Store & CQRS ([reckon-db-org](https://github.com/reckon-db-org))

BEAM-native event sourcing infrastructure.

| Package | Description | Links |
|---------|-------------|-------|
| **reckon_db** | BEAM-native event store built on Khepri/Ra | [GitHub](https://github.com/reckon-db-org/reckon-db) \| [HexDocs](https://hexdocs.pm/reckon_db) |
| **reckon_gater** | Gateway for distributed event store access | [GitHub](https://github.com/reckon-db-org/reckon-gater) \| [HexDocs](https://hexdocs.pm/reckon_gater) |
| **evoq** | Event sourcing primitives (aggregates, commands, events) | [GitHub](https://github.com/reckon-db-org/evoq) \| [HexDocs](https://hexdocs.pm/evoq) |
| **reckon_evoq** | Adapter connecting Evoq to ReckonDB | [GitHub](https://github.com/reckon-db-org/reckon-evoq) \| [HexDocs](https://hexdocs.pm/reckon_evoq) |

**Core capabilities:**
- **Raft Consensus** — Strong consistency via Ra (Erlang Raft implementation)
- **Event Replay** — Full audit trail and time-travel debugging
- **CQRS Patterns** — Command/query separation with projections
- **Distributed Clusters** — Automatic discovery via LibCluster

## Data Flow

<p align="center">
  <img src="assets/data-flow.svg" alt="Event-Sourced Application Data Flow" width="100%">
</p>

## Documentation

- [**Overview**](guides/overview.md) - Introduction to the ecosystem
- [**Architecture**](guides/architecture.md) - How the pieces fit together
- [**Getting Started**](guides/getting-started.md) - Build your first app
- [**Event Sourcing**](guides/event-sourcing.md) - CQRS/ES patterns
- [**Mesh Networking**](guides/mesh-networking.md) - HTTP/3 mesh guide
- [**Content Transfer**](guides/content-transfer.md) - P2P artifact distribution
- [**Neuroevolution**](guides/neuroevolution.md) - TWEANN and NEAT
- [**MaculaOS**](guides/macula-os.md) - Edge deployment

## Why Macula?

### Reclaim Your Place in the AI Economy

AI is rapidly automating cognitive work, displacing millions from traditional employment. But AI needs compute—and that's an opportunity. Macula transforms you from a **displaced worker** into an **infrastructure provider**:

- **Compute as a new asset class** - Your hardware becomes income-generating infrastructure
- **Run micro-datacenters** - Participate in the mesh economy from your home or office
- **Own your contribution** - No middleman taking 30%+ of your compute value
- **Community-owned AI** - Train and run models on community infrastructure, not Big Tech clouds

### A Platform for Indies and Solo Developers

Big Tech platforms demand 30% cuts, dictate your terms, and can deplatform you overnight. Macula puts a **production-ready distributed platform at your fingertips**:

- **Zero platform fees** - Keep 100% of what you earn
- **No app store gatekeepers** - Deploy directly to your users
- **Built-in distribution** - Your app runs on the mesh, scales with demand
- **Own your relationship** - Direct connection to users, no algorithm deciding your fate

### Break Free from Big Tech

Five companies control most cloud infrastructure, creating vendor lock-in and data exploitation. Macula provides **infrastructure you own**:

- **Local data processing** - Your data never leaves your network
- **Open standards** - No proprietary lock-in, no platform risk
- **Portable workloads** - Move freely between nodes and providers

### Data Sovereignty by Design

Governments worldwide enforce strict data residency requirements (GDPR, CCPA, localization laws). Macula's edge-first architecture naturally complies:

- **Processing where data is created** - No cross-border transfers
- **Cryptographic authorization** - UCAN tokens, not central auth servers
- **Audit trails** - Event sourcing captures every state change

### Digital Resilience

Centralized systems fail catastrophically. Macula's mesh architecture ensures continuity:

- **If node A fails, nodes B, C, D continue** - No single point of failure
- **Offline-capable** - Nodes operate independently when disconnected
- **Eventual consistency** - Changes propagate when connectivity returns

### Environmental Efficiency

Data centers consume significant global electricity while operating at only 15-25% utilization. Edge processing changes this:

- **10x energy reduction** for local processing vs cloud round-trips
- **Utilize existing hardware** - Any device can join the mesh
- **Reduce network overhead** - Process data where it's generated

### BEAM-Native Excellence

Every component is built on the BEAM (Erlang VM), battle-tested in telecom for 40+ years:

- **Fault tolerance** - Supervisors restart failed processes automatically
- **Soft real-time** - Predictable latency characteristics
- **Hot code loading** - Deploy without downtime
- **Massive concurrency** - Millions of lightweight processes

## Use Cases

- **IoT Platforms** - Collect and process sensor data at the edge
- **Financial Systems** - Complete audit trails with event sourcing
- **Gaming** - Real-time multiplayer on a mesh network
- **Robotics** - Evolve controllers with neuroevolution
- **Healthcare** - Decentralized patient data with UCAN authorization

## Community

- **GitHub**: [macula-io](https://github.com/macula-io) | [reckon-db-org](https://github.com/reckon-db-org) | [beam-campus](https://github.com/beam-campus)
- **Hex.pm**: Search for `macula`, `reckon`, or `bc_gitops`
- **Issues**: Report bugs on the respective repositories

## License

Apache 2.0 - See [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with the BEAM</sub>
</p>
