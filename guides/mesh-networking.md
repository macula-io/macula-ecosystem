# Mesh Networking Guide

This guide covers the Macula mesh networking layer - a decentralized
communication platform built on HTTP/3 (QUIC) transport.

## Overview

The Macula mesh enables:

- **Decentralized discovery** - Find services without central registry
- **NAT traversal** - Connect peers behind firewalls
- **Pub/Sub messaging** - Broadcast events to interested parties
- **RPC calls** - Request/response patterns across the mesh
- **Multi-tenancy** - Isolated realms for different applications

## Core Concepts

### Realms

A realm is an isolated namespace within the mesh:

```
io.macula.production     # Production environment
io.macula.staging        # Staging environment
io.acme.inventory        # ACME's inventory service
io.acme.orders           # ACME's order service
```

Nodes in different realms cannot communicate directly - this provides
isolation for multi-tenant deployments.

### DIDs (Decentralized Identifiers)

Every node has a unique identity:

```
did:macula:io.acme.orders.node-1
        │      │          │
        │      │          └─ Node identifier
        │      └─ Realm
        └─ Method (macula mesh)
```

DIDs are cryptographically verifiable - no central authority required.

### Topics and Procedures

**Topics** are for pub/sub (many subscribers):

```
io.acme.orders.order_placed      # Event topic
io.acme.inventory.stock_updated  # Event topic
```

**Procedures** are for RPC (one handler):

```
io.acme.orders.place_order       # RPC procedure
io.acme.inventory.check_stock    # RPC procedure
```

## Getting Started

### Installation

Add Macula to your dependencies:

```elixir
# mix.exs
defp deps do
  [
    {:macula, "~> 0.17"}
  ]
end
```

### Configuration

```elixir
# config/config.exs
config :macula,
  realm: "io.myapp",
  bootstrap_nodes: [
    "bootstrap.macula.io:4433",
    "eu.bootstrap.macula.io:4433"
  ],
  quic_port: 4433
```

### Connecting to the Mesh

```elixir
# Start a mesh client
{:ok, client} = :macula.connect([
  realm: "io.myapp",
  node_id: "service-1"
])

# Client is now connected and discoverable
```

## RPC (Remote Procedure Calls)

### Advertising a Procedure

Make your service callable from anywhere in the mesh:

```elixir
# Define a handler function
def handle_get_order(%{order_id: id}) do
  case MyApp.Orders.get(id) do
    nil -> {:error, :not_found}
    order -> {:ok, order}
  end
end

# Advertise the procedure
:ok = :macula.advertise(client, "io.myapp.orders.get_order", &handle_get_order/1)
```

### Calling a Procedure

Call any advertised procedure in the mesh:

```elixir
# Synchronous call
{:ok, order} = :macula.call(client, "io.myapp.orders.get_order", %{order_id: "123"})

# With timeout
{:ok, order} = :macula.call(client, "io.myapp.orders.get_order", %{order_id: "123"}, timeout: 5000)

# Async call
ref = :macula.call_async(client, "io.myapp.orders.get_order", %{order_id: "123"})
receive do
  {:macula_result, ^ref, {:ok, order}} -> handle_order(order)
  {:macula_result, ^ref, {:error, reason}} -> handle_error(reason)
after
  5000 -> handle_timeout()
end
```

### Load Balancing

When multiple nodes advertise the same procedure, calls are automatically
load-balanced:

```
Node A: advertises "io.myapp.orders.get_order"
Node B: advertises "io.myapp.orders.get_order"
Node C: advertises "io.myapp.orders.get_order"

call("io.myapp.orders.get_order") → routes to A, B, or C
```

## Pub/Sub (Publish/Subscribe)

### Publishing Events

Broadcast events to all interested subscribers:

```elixir
# Publish an event
:ok = :macula.publish(client, "io.myapp.orders.order_placed", %{
  order_id: "123",
  customer_id: "456",
  total: 99.99
})
```

### Subscribing to Events

Receive events matching a pattern:

```elixir
# Subscribe to a specific topic
:ok = :macula.subscribe(client, "io.myapp.orders.order_placed", fn event ->
  IO.inspect(event, label: "Order placed")
end)

# Subscribe with wildcard (all order events)
:ok = :macula.subscribe(client, "io.myapp.orders.*", fn event, topic ->
  IO.inspect({topic, event}, label: "Order event")
end)
```

### Topic Naming

Follow the naming convention from the ecosystem:

- **Events**: `{realm}.{domain}.{subject}_{past_tense_verb}`
  - `io.myapp.orders.order_placed`
  - `io.myapp.inventory.stock_depleted`
  - `io.myapp.payments.payment_received`

- **Avoid CRUD verbs**: Use business-meaningful names
  - `order_placed` not `order_created`
  - `user_promoted` not `user_updated`

## DHT (Distributed Hash Table)

The mesh uses a Kademlia-based DHT for decentralized discovery.

### How Discovery Works

```
┌──────────────────────────────────────────────────────────────┐
│  1. Node A advertises "io.acme.orders.get_order"             │
│     → DHT stores: hash("io.acme.orders.get_order") → Node A  │
├──────────────────────────────────────────────────────────────┤
│  2. Node B wants to call "io.acme.orders.get_order"          │
│     → DHT lookup: hash("io.acme.orders.get_order")           │
│     → Returns: Node A                                        │
├──────────────────────────────────────────────────────────────┤
│  3. Node B connects directly to Node A                       │
│     → QUIC connection established                            │
│     → RPC call executed                                      │
└──────────────────────────────────────────────────────────────┘
```

### DHT Operations

```elixir
# Get DHT statistics
stats = :macula.dht_stats(client)
# => %{nodes: 42, buckets: 160, stored_keys: 1234}

# Lookup a key (for debugging)
{:ok, nodes} = :macula.dht_lookup(client, "io.acme.orders.get_order")
# => [%{node_id: "node-1", address: "192.168.1.100:4433"}, ...]
```

## Authorization (UCAN)

The mesh uses UCAN (User Controlled Authorization Networks) for
capability-based security.

### Creating a UCAN Token

```elixir
# Create a token granting read access to orders
{:ok, ucan} = :macula.create_ucan(
  issuer_did: "did:macula:io.acme.admin",
  audience_did: "did:macula:io.acme.reporting",
  capabilities: [
    %{with: "io.acme.orders.*", can: "read"},
    %{with: "io.acme.orders.get_order", can: "invoke"}
  ],
  expires_in: 3600  # 1 hour
)
```

### Using UCAN for Calls

```elixir
# Make an authorized call
{:ok, result} = :macula.call(client, "io.acme.orders.get_order",
  %{order_id: "123"},
  ucan: ucan
)
```

### Authorization Checks

```elixir
# In your RPC handler
def handle_get_order(args, context) do
  # Context includes caller's DID and capabilities
  if authorized?(context, "io.acme.orders", "read") do
    {:ok, get_order(args.order_id)}
  else
    {:error, :unauthorized}
  end
end

defp authorized?(context, resource, action) do
  :macula.check_capability(context.ucan, resource, action)
end
```

## NAT Traversal

The mesh handles NAT traversal automatically using STUN/TURN:

### Connection Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. STUN: Discover public IP and port                           │
│     Node → STUN Server → "Your public address is 1.2.3.4:5678"  │
├─────────────────────────────────────────────────────────────────┤
│  2. Direct Connection Attempt                                    │
│     Node A ←────────────────────────────────────────→ Node B    │
│     If successful: Use direct QUIC connection                   │
├─────────────────────────────────────────────────────────────────┤
│  3. Relay Fallback (if direct fails)                            │
│     Node A ←→ TURN Relay ←→ Node B                              │
│     Works even with symmetric NAT                               │
└─────────────────────────────────────────────────────────────────┘
```

### NAT Type Detection

```elixir
# Check your NAT type
nat_info = :macula.nat_info(client)
# => %{
#      type: :full_cone,           # or :restricted, :port_restricted, :symmetric
#      public_ip: "1.2.3.4",
#      public_port: 5678,
#      hairpin: true
#    }
```

## Error Handling

### Connection Errors

```elixir
case :macula.call(client, procedure, args) do
  {:ok, result} ->
    handle_success(result)

  {:error, :not_found} ->
    # Procedure not advertised
    handle_not_found()

  {:error, :timeout} ->
    # Call timed out
    handle_timeout()

  {:error, :disconnected} ->
    # Lost mesh connection
    reconnect()

  {:error, {:remote, reason}} ->
    # Handler returned an error
    handle_remote_error(reason)
end
```

### Reconnection

The client automatically reconnects on network failures:

```elixir
# Configure reconnection behavior
{:ok, client} = :macula.connect([
  realm: "io.myapp",
  reconnect: true,
  reconnect_interval: 5000,  # 5 seconds
  max_reconnect_attempts: 10
])
```

## Monitoring

### Telemetry Events

Macula emits telemetry events for monitoring:

```elixir
# Attach to telemetry events
:telemetry.attach(
  "macula-metrics",
  [:macula, :call, :stop],
  fn _event, measurements, metadata, _config ->
    # Log RPC call duration
    Logger.info("RPC #{metadata.procedure} took #{measurements.duration}ms")
  end,
  nil
)
```

### Available Events

| Event | Description |
|-------|-------------|
| `[:macula, :call, :start]` | RPC call initiated |
| `[:macula, :call, :stop]` | RPC call completed |
| `[:macula, :publish, :stop]` | Event published |
| `[:macula, :subscribe, :stop]` | Subscription created |
| `[:macula, :connection, :up]` | Peer connected |
| `[:macula, :connection, :down]` | Peer disconnected |

## Best Practices

### 1. Use Meaningful Topic Names

```elixir
# Good: Business-meaningful
"io.myapp.orders.order_placed"
"io.myapp.inventory.stock_depleted"

# Bad: Technical/CRUD
"io.myapp.orders.created"
"io.myapp.db.update"
```

### 2. Keep Payloads Small

QUIC has excellent performance, but smaller is still faster:

```elixir
# Good: Only what's needed
%{order_id: "123", status: "shipped"}

# Bad: Entire object graph
%{order: %{...}, customer: %{...}, items: [...], history: [...]}
```

### 3. Handle Partitions Gracefully

The mesh is eventually consistent - design for partitions:

```elixir
# Retry with backoff
def call_with_retry(client, procedure, args, attempts \\ 3) do
  case :macula.call(client, procedure, args) do
    {:ok, result} -> {:ok, result}
    {:error, :timeout} when attempts > 0 ->
      Process.sleep(1000 * (4 - attempts))  # Exponential backoff
      call_with_retry(client, procedure, args, attempts - 1)
    error -> error
  end
end
```

### 4. Use Appropriate Timeouts

Different operations need different timeouts:

```elixir
# Fast lookup
:macula.call(client, "get_status", %{}, timeout: 1000)

# Complex operation
:macula.call(client, "generate_report", %{}, timeout: 30000)
```

## Next Steps

- [Architecture Guide](architecture.md) - See how mesh fits in the ecosystem
- [Event Sourcing Guide](event-sourcing.md) - Combine mesh with event sourcing
- [Getting Started](getting-started.md) - Build your first app
