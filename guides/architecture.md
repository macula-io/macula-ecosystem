# Architecture

This guide explains how the Macula ecosystem components fit together to create
a complete distributed application platform.

## Layered Architecture

The ecosystem is organized into distinct layers, each with a specific responsibility:

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOUR APPLICATION                              │
│         Phoenix LiveView, Business Logic, Read Models            │
├─────────────────────────────────────────────────────────────────┤
│                    INTELLIGENCE LAYER                            │
│       macula_neuroevolution, macula_tweann (optional)           │
├─────────────────────────────────────────────────────────────────┤
│                      MESH LAYER                                  │
│                        macula                                    │
│              HTTP/3 over QUIC, DHT, PubSub, RPC                 │
├─────────────────────────────────────────────────────────────────┤
│                    GATEWAY LAYER                                 │
│                     reckon_gater                                 │
│            Load Balancing, Routing, Authorization                │
├─────────────────────────────────────────────────────────────────┤
│                 EVENT SOURCING LAYER                             │
│                   evoq + reckon_evoq                             │
│            Aggregates, Commands, Events, Projections             │
├─────────────────────────────────────────────────────────────────┤
│                   PERSISTENCE LAYER                              │
│                      reckon_db                                   │
│               Khepri/Ra Raft Consensus Event Store               │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

![Data Flow](assets/data-flow.svg)

### Command Path (Write)

1. **User Action** → Your application receives a request
2. **Command Dispatch** → Evoq validates and dispatches the command
3. **Aggregate** → Business logic determines what events to emit
4. **Event Adapter** → ReckonEvoq routes events to the store
5. **Gateway** → ReckonGater handles routing and authorization
6. **Event Store** → ReckonDB persists events via Raft consensus

### Query Path (Read)

1. **Event Published** → ReckonDB notifies subscribers
2. **Projection** → Your code updates read models
3. **Read Model** → Optimized for queries (no joins, pre-computed)
4. **Query** → Application queries the read model directly

### Mesh Communication

1. **Advertise** → Service registers with DHT
2. **Discover** → Client finds service via DHT lookup
3. **Call/Publish** → HTTP/3 request over QUIC
4. **Respond/Subscribe** → Bidirectional streaming

## Package Responsibilities

### reckon_db - Event Store

The foundation. Stores events in append-only streams with:

- **Raft consensus** via Khepri/Ra for distributed agreement
- **Stream-based storage** with optimistic concurrency
- **Global ordering** for causality tracking
- **Subscriptions** for real-time event delivery

```erlang
%% Append events to a stream
reckon_db:append(Store, "order-123", [OrderPlaced, OrderShipped]).

%% Subscribe to events
reckon_db:subscribe(Store, "order-*", fun(Event) -> handle(Event) end).
```

### reckon_gater - Gateway

Distributed access layer providing:

- **Load balancing** across store nodes
- **UCAN authorization** for capability-based security
- **Routing** for multi-tenant deployments
- **Connection pooling** and retry logic

```erlang
%% Connect through gateway
{ok, Client} = reckon_gater:connect(GatewayNodes).

%% Operations are routed automatically
reckon_gater:append(Client, Stream, Events).
```

### evoq - Event Sourcing Primitives

CQRS/ES building blocks:

- **Aggregates** - Encapsulate business rules
- **Commands** - Requests to change state
- **Events** - Facts about what happened
- **Process Managers** - Coordinate multi-aggregate workflows

```elixir
defmodule MyApp.Orders.Aggregate do
  use Evoq.Aggregate

  def execute(%PlaceOrder{} = cmd, state) do
    {:ok, [%OrderPlaced{order_id: cmd.order_id, items: cmd.items}]}
  end

  def apply(%OrderPlaced{} = event, state) do
    %{state | status: :placed, items: event.items}
  end
end
```

### reckon_evoq - Adapter

Bridges Evoq and ReckonDB:

- **Stream mapping** - Aggregate ID → Event stream
- **Subscription routing** - Events to projections
- **Snapshot management** - Periodic state capture

```elixir
config :evoq,
  event_store: ReckonEvoq.EventStore,
  repo: MyApp.ReckonRepo
```

### macula - Mesh Networking

HTTP/3 mesh over QUIC providing:

- **DHT** - Distributed hash table for service discovery
- **PubSub** - Decentralized publish/subscribe
- **RPC** - Request/response patterns
- **NAT traversal** - STUN/TURN for connectivity

```erlang
%% Advertise a service
macula:advertise(Client, "my.service.procedure", Handler).

%% Call a remote service
{ok, Result} = macula:call(Client, "my.service.procedure", Args).

%% Publish an event
macula:publish(Client, "my.domain.event_occurred", Payload).
```

### macula_tweann - Neural Networks

Topology and Weight Evolving Artificial Neural Networks:

- **Dynamic topologies** - Networks that grow and shrink
- **Substrate encoding** - Spatial neural patterns
- **Neuromodulation** - Adaptive learning rates

### macula_neuroevolution - Evolution Framework

Genetic algorithms for neural network evolution:

- **NEAT** - NeuroEvolution of Augmenting Topologies
- **HyperNEAT** - Indirect encoding via CPPNs
- **Population management** - Speciation and selection

## Integration Patterns

### Pattern 1: Event-Sourced Microservices

```
Service A                    Service B
    │                            │
    ├─ Command ─────────────────►│
    │                            ├─ Process Command
    │                            │
    │◄──────── Event ────────────┤
    │                            │
    ├─ Update Projection         │
    │                            │
```

Services communicate via events through the mesh. Each service:
- Owns its aggregate and event streams
- Subscribes to relevant events from other services
- Maintains its own read models

### Pattern 2: CQRS with Projections

```
                    ┌─────────────┐
Command ───────────►│  Aggregate  │
                    └──────┬──────┘
                           │ Events
                           ▼
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
     ┌────────────────┐       ┌────────────────┐
     │ Projection A   │       │ Projection B   │
     │ (List View)    │       │ (Analytics)    │
     └────────┬───────┘       └────────┬───────┘
              │                        │
              ▼                        ▼
     ┌────────────────┐       ┌────────────────┐
     │  Read Model A  │       │  Read Model B  │
     │  (PostgreSQL)  │       │  (ClickHouse)  │
     └────────────────┘       └────────────────┘
```

Multiple projections consume the same events to build different read models
optimized for specific query patterns.

### Pattern 3: Saga / Process Manager

```
┌─────────────────────────────────────────────────────────────┐
│                    Order Fulfillment Saga                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  OrderPlaced ──► ReserveInventory ──► InventoryReserved     │
│                                              │               │
│                                              ▼               │
│  ShipmentCreated ◄── CreateShipment ◄── (continue)          │
│         │                                                    │
│         ▼                                                    │
│  MarkOrderShipped ──► OrderShipped                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

Process managers coordinate multi-step workflows by:
- Listening for trigger events
- Dispatching commands to aggregates
- Tracking saga state
- Handling compensating actions on failure

### Pattern 4: Edge Deployment

```
┌─────────────────────┐     ┌─────────────────────┐
│    Edge Node A      │     │    Edge Node B      │
│  ┌───────────────┐  │     │  ┌───────────────┐  │
│  │  Local Store  │  │     │  │  Local Store  │  │
│  │  (ReckonDB)   │  │     │  │  (ReckonDB)   │  │
│  └───────────────┘  │     │  └───────────────┘  │
│         │           │     │         │           │
│         ▼           │     │         ▼           │
│  ┌───────────────┐  │     │  ┌───────────────┐  │
│  │   Macula      │◄─┼─────┼─►│   Macula      │  │
│  │   Mesh        │  │     │  │   Mesh        │  │
│  └───────────────┘  │     │  └───────────────┘  │
└─────────────────────┘     └─────────────────────┘
          │                           │
          └───────────┬───────────────┘
                      ▼
            ┌─────────────────┐
            │   Cloud Hub     │
            │  (Optional)     │
            └─────────────────┘
```

Edge nodes operate autonomously with local event stores, synchronizing
via the mesh when connectivity permits.

## Consistency Models

### Event Store (ReckonDB)

- **Strong consistency** within a stream (Raft consensus)
- **Eventual consistency** across streams
- **Causal ordering** via global sequence numbers

### Mesh (Macula)

- **Eventual consistency** for DHT state
- **At-least-once delivery** for pub/sub
- **Exactly-once semantics** available with deduplication

### Read Models

- **Eventual consistency** by design
- **Idempotent projections** handle replay
- **Version tracking** for staleness detection

## Security Model

### UCAN (User Controlled Authorization Networks)

The ecosystem uses UCAN tokens for capability-based security:

```
┌────────────────────────────────────────────────────────────┐
│                      UCAN Token                             │
├────────────────────────────────────────────────────────────┤
│  Issuer:    did:macula:io.example.alice                    │
│  Audience:  did:macula:io.example.bob                      │
│  Capabilities:                                              │
│    - { with: "io.example.orders.*", can: "read" }          │
│    - { with: "io.example.orders.create", can: "invoke" }   │
│  Expiry:    2024-12-31T23:59:59Z                           │
│  Signature: Ed25519(...)                                    │
└────────────────────────────────────────────────────────────┘
```

Key properties:
- **Decentralized** - No central authority required
- **Delegatable** - Tokens can be attenuated and passed on
- **Cryptographically verifiable** - No network calls to validate

## Next Steps

- [Getting Started](getting-started.md) - Build your first application
- [Event Sourcing Guide](event-sourcing.md) - Deep dive into CQRS/ES
- [Mesh Networking Guide](mesh-networking.md) - Learn the mesh API
