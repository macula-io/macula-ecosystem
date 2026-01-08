# Overview

The Macula Ecosystem is a collection of BEAM-native libraries for building
distributed, event-sourced applications that run on a decentralized mesh network.

## Two Organizations, One Vision

The ecosystem spans two GitHub organizations with complementary responsibilities:

### reckon-db-org - Infrastructure Layer

The foundation for event sourcing and persistence:

| Package | Description |
|---------|-------------|
| [reckon_db](https://hexdocs.pm/reckon_db) | BEAM-native event store built on Khepri/Ra consensus |
| [reckon_gater](https://hexdocs.pm/reckon_gater) | Gateway for distributed event store access |
| [evoq](https://hexdocs.pm/evoq) | Event sourcing primitives (aggregates, commands, events) |
| [reckon_evoq](https://hexdocs.pm/reckon_evoq) | Adapter connecting Evoq to ReckonDB |

### macula-io - Application Layer

The distributed application platform:

| Package | Description |
|---------|-------------|
| [macula](https://hexdocs.pm/macula) | HTTP/3 mesh networking over QUIC |
| [macula_tweann](https://hexdocs.pm/macula_tweann) | TWEANN neural network topologies |
| [macula_neuroevolution](https://hexdocs.pm/macula_neuroevolution) | Neuroevolution framework |
| [macula_console](https://github.com/macula-io/macula-console) | Management console |
| [macula_os](https://github.com/macula-io/macula-os) | Edge node operating system |

## The Big Picture

![Ecosystem Overview](assets/ecosystem-overview.svg)

The architecture follows a layered approach:

1. **Persistence Layer** - ReckonDB stores events with Raft consensus
2. **Event Sourcing Layer** - Evoq provides CQRS/ES patterns
3. **Gateway Layer** - ReckonGater provides distributed access
4. **Mesh Layer** - Macula connects nodes via HTTP/3
5. **Application Layer** - Your business logic
6. **Intelligence Layer** - Neuroevolution for adaptive behavior

## Why This Architecture?

### Event Sourcing + Mesh = Resilience

Traditional architectures couple storage and computation. When a server fails,
both are lost. The Macula approach separates concerns:

- **Events are facts** - Immutable records of what happened
- **State is derived** - Rebuilt from events on any node
- **Mesh is location-agnostic** - Services move freely between nodes

### BEAM-Native = Operational Excellence

Every component is built on the BEAM (Erlang VM):

- **Fault tolerance** - Supervisors restart failed processes
- **Distribution** - Built-in clustering primitives
- **Hot code loading** - Deploy without downtime
- **Soft real-time** - Predictable latency characteristics

### Edge-First = True Decentralization

The platform is designed for edge deployment:

- **Local autonomy** - Nodes operate independently when disconnected
- **Eventual consistency** - Changes propagate when connectivity returns
- **No single point of failure** - No master node required

## Getting Started

Ready to build? Jump to the [Getting Started Guide](getting-started.md).

Want to understand the architecture first? See the [Architecture Guide](architecture.md).

## Use Cases

### Event-Sourced Applications

Build applications where every state change is captured as an immutable event:

- **Audit trails** - Complete history of all changes
- **Time travel** - Reconstruct state at any point in time
- **Event replay** - Rebuild read models from scratch
- **CQRS** - Separate read and write paths

### Distributed Services

Deploy services across a mesh network:

- **Service discovery** - Find services via DHT
- **Load balancing** - Distribute requests across instances
- **Fault tolerance** - Automatic failover
- **Cross-node communication** - RPC and pub/sub

### Edge Computing

Run workloads at the edge of the network:

- **IoT gateways** - Process data locally
- **Offline-first apps** - Work without connectivity
- **Low latency** - Compute near the data source
- **Resource efficiency** - Minimal footprint

### Adaptive Systems

Build systems that evolve and improve:

- **Neuroevolution** - Evolve neural network topologies
- **Genetic algorithms** - Optimize parameters over time
- **Self-healing** - Adapt to changing conditions

## Community

- **GitHub**: [github.com/macula-io](https://github.com/macula-io) | [github.com/reckon-db-org](https://github.com/reckon-db-org)
- **Hex.pm**: Search for `macula` or `reckon`
- **Issues**: Report bugs or request features on the respective repositories

## License

All packages in the ecosystem are released under the Apache 2.0 license.
