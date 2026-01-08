# Event Sourcing Guide

This guide covers event sourcing patterns and best practices using the
ReckonDB + Evoq stack.

## What is Event Sourcing?

Event sourcing is an architectural pattern where:

1. **State changes are captured as events** - Instead of storing current state,
   we store the sequence of events that led to that state.

2. **Events are immutable facts** - Once recorded, events never change. They
   represent things that happened in the past.

3. **State is derived** - Current state is computed by replaying events from
   the beginning (or from a snapshot).

## Why Event Sourcing?

### Complete Audit Trail

Every change is recorded. You can answer questions like:
- What was the order status on Tuesday at 3pm?
- Who changed this value and when?
- What sequence of actions led to this state?

### Temporal Queries

Reconstruct state at any point in time:

```elixir
# Get order state as of a specific time
{:ok, state} = ReckonDB.load_aggregate("order-123", until: ~U[2024-01-15 14:30:00Z])
```

### Event Replay

Rebuild read models from scratch without data migration:

```elixir
# Replay all events to rebuild a projection
ReckonDB.replay("orders.*", fn event, metadata ->
  MyProjection.handle(event, metadata)
end)
```

### Debugging

Reproduce exact scenarios by replaying the same event sequence in tests.

## Core Concepts

### Events

Events are **past-tense facts** about what happened:

```elixir
defmodule MyApp.Orders.OrderPlaced do
  @moduledoc """
  Emitted when a customer successfully places an order.

  This event captures the complete order details at the moment
  of placement, enabling accurate historical reconstruction.
  """

  use Evoq.Event

  embedded_schema do
    field :order_id, :string
    field :customer_id, :string
    field :items, {:array, :map}
    field :total_amount, :decimal
    field :currency, :string, default: "EUR"
    field :placed_at, :utc_datetime
  end
end
```

**Naming Convention**: `{Subject}_{PastTenseVerb}`
- `OrderPlaced` not `PlaceOrder` or `OrderCreated`
- `PaymentReceived` not `ReceivePayment`
- `InventoryReserved` not `ReserveInventory`

**Never use CRUD verbs**: `Created`, `Updated`, `Deleted` tell us nothing
about business intent.

### Commands

Commands are **requests to do something**:

```elixir
defmodule MyApp.Orders.PlaceOrderV1 do
  @moduledoc "Request to place a new order."

  use Evoq.Command

  embedded_schema do
    field :order_id, :string
    field :customer_id, :string
    field :items, {:array, :map}
  end

  def changeset(command, attrs) do
    command
    |> cast(attrs, [:order_id, :customer_id, :items])
    |> validate_required([:order_id, :customer_id, :items])
  end
end
```

**Naming Convention**: `{Verb}{Subject}V{Version}`
- Version suffix enables backward-compatible evolution
- `PlaceOrderV1`, `PlaceOrderV2` can coexist

### Aggregates

Aggregates **enforce business invariants**:

```elixir
defmodule MyApp.Orders.Aggregate do
  use Evoq.Aggregate

  defstruct [
    :order_id,
    :status,
    :items,
    :total_amount,
    :payment_status
  ]

  # ─────────────────────────────────────────────────────────
  # Command Handlers - Decide what events to emit
  # ─────────────────────────────────────────────────────────

  def execute(%PlaceOrderV1{} = cmd, nil) do
    # Business rule: New orders start in :pending status
    {:ok, [%OrderPlaced{...}]}
  end

  def execute(%PlaceOrderV1{}, %{order_id: _}) do
    # Business rule: Can't place an order that already exists
    {:error, :order_already_exists}
  end

  def execute(%ShipOrderV1{}, %{status: :pending}) do
    # Business rule: Can't ship unpaid orders
    {:error, :payment_required}
  end

  def execute(%ShipOrderV1{} = cmd, %{status: :paid}) do
    {:ok, [%OrderShipped{...}]}
  end

  # ─────────────────────────────────────────────────────────
  # Event Handlers - Update state from events
  # ─────────────────────────────────────────────────────────

  def apply(%OrderPlaced{} = e, _state) do
    %__MODULE__{
      order_id: e.order_id,
      status: :pending,
      items: e.items,
      total_amount: e.total_amount
    }
  end

  def apply(%PaymentReceived{}, state) do
    %{state | status: :paid, payment_status: :complete}
  end

  def apply(%OrderShipped{}, state) do
    %{state | status: :shipped}
  end
end
```

### Streams

Events are organized into **streams** - ordered sequences of related events:

```
Stream: "order-abc123"
├── 1: OrderPlaced { ... }
├── 2: PaymentReceived { ... }
├── 3: OrderShipped { ... }
└── 4: OrderDelivered { ... }
```

Stream naming convention: `{aggregate_type}-{aggregate_id}`

## Projections

Projections transform events into **read models** optimized for queries.

### Design Principles

1. **No joins in queries** - Denormalize everything
2. **No calculations in queries** - Pre-compute in projections
3. **Idempotent handlers** - Safe to replay

```elixir
defmodule MyApp.Projections.OrderPlacedToOrders do
  use Evoq.Projection

  alias MyApp.ReadModels.Order

  def handle(%OrderPlaced{} = event, metadata) do
    attrs = %{
      id: event.order_id,
      customer_id: event.customer_id,
      customer_name: lookup_customer_name(event.customer_id),  # Denormalize!
      items: event.items,
      item_count: length(event.items),  # Pre-compute!
      total_amount: event.total_amount,
      status: "placed",
      placed_at: event.placed_at,
      stream_position: metadata.position  # For idempotency
    }

    %Order{}
    |> Order.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id]},
      conflict_target: :id
    )

    :ok
  end
end
```

### Multiple Projections Per Event

One event can update multiple read models:

```elixir
# Projection 1: Order list view
defmodule OrderPlacedToOrders do
  def handle(%OrderPlaced{} = e, _) do
    # Update orders table
  end
end

# Projection 2: Customer order count
defmodule OrderPlacedToCustomerStats do
  def handle(%OrderPlaced{} = e, _) do
    # Increment customer's order count
    Repo.update_all(
      from(c in CustomerStats, where: c.id == ^e.customer_id),
      inc: [order_count: 1, total_spent: e.total_amount]
    )
  end
end

# Projection 3: Daily sales analytics
defmodule OrderPlacedToDailySales do
  def handle(%OrderPlaced{} = e, _) do
    date = DateTime.to_date(e.placed_at)
    # Upsert daily totals
  end
end
```

## Process Managers (Sagas)

Process managers coordinate workflows spanning multiple aggregates:

```elixir
defmodule MyApp.ProcessManagers.OrderFulfillment do
  use Evoq.ProcessManager

  # ─────────────────────────────────────────────────────────
  # State
  # ─────────────────────────────────────────────────────────

  defstruct [
    :order_id,
    :status,
    :inventory_reserved,
    :payment_received,
    :shipment_created
  ]

  # ─────────────────────────────────────────────────────────
  # Routing - Which events start/continue this process?
  # ─────────────────────────────────────────────────────────

  def interested?(%OrderPlaced{order_id: id}), do: {:start, id}
  def interested?(%PaymentReceived{order_id: id}), do: {:continue, id}
  def interested?(%InventoryReserved{order_id: id}), do: {:continue, id}
  def interested?(%ShipmentCreated{order_id: id}), do: {:continue, id}
  def interested?(_), do: false

  # ─────────────────────────────────────────────────────────
  # Event Handlers - React to events
  # ─────────────────────────────────────────────────────────

  def handle(%OrderPlaced{} = event, state) do
    # Order placed - reserve inventory
    command = %ReserveInventoryV1{
      order_id: event.order_id,
      items: event.items
    }

    new_state = %{state | order_id: event.order_id, status: :awaiting_inventory}

    {:dispatch, command, new_state}
  end

  def handle(%InventoryReserved{}, state) do
    new_state = %{state | inventory_reserved: true}

    if state.payment_received do
      # Both conditions met - create shipment
      {:dispatch, %CreateShipmentV1{order_id: state.order_id}, new_state}
    else
      {:ok, %{new_state | status: :awaiting_payment}}
    end
  end

  def handle(%PaymentReceived{}, state) do
    new_state = %{state | payment_received: true}

    if state.inventory_reserved do
      # Both conditions met - create shipment
      {:dispatch, %CreateShipmentV1{order_id: state.order_id}, new_state}
    else
      {:ok, %{new_state | status: :awaiting_inventory}}
    end
  end

  def handle(%ShipmentCreated{}, state) do
    # Workflow complete
    {:stop, %{state | status: :complete, shipment_created: true}}
  end

  # ─────────────────────────────────────────────────────────
  # Error Handling - Compensating actions
  # ─────────────────────────────────────────────────────────

  def handle(%InventoryReservationFailed{reason: reason}, state) do
    # Compensate: Cancel the order
    command = %CancelOrderV1{
      order_id: state.order_id,
      reason: "Inventory unavailable: #{reason}"
    }

    {:dispatch, command, %{state | status: :cancelled}}
  end
end
```

## Advanced Patterns

### Event Versioning

As your domain evolves, events may need to change:

```elixir
defmodule MyApp.Events.OrderPlacedV1 do
  embedded_schema do
    field :order_id, :string
    field :items, {:array, :map}
  end
end

defmodule MyApp.Events.OrderPlacedV2 do
  # V2 adds currency support
  embedded_schema do
    field :order_id, :string
    field :items, {:array, :map}
    field :currency, :string  # New field
  end
end
```

Use upcasters to convert old events:

```elixir
defmodule MyApp.Upcasters.OrderPlaced do
  def upcast(%OrderPlacedV1{} = v1) do
    %OrderPlacedV2{
      order_id: v1.order_id,
      items: v1.items,
      currency: "EUR"  # Default for old events
    }
  end

  def upcast(%OrderPlacedV2{} = v2), do: v2
end
```

### Snapshots

For aggregates with many events, snapshots improve load time:

```elixir
defmodule MyApp.Orders.Aggregate do
  use Evoq.Aggregate, snapshot_every: 100

  # After every 100 events, a snapshot is taken
  # Loading starts from the latest snapshot
end
```

### Event Enrichment

Add metadata to events for debugging and analytics:

```elixir
def dispatch_with_context(command, opts) do
  metadata = %{
    user_id: opts[:current_user].id,
    correlation_id: opts[:correlation_id] || UUID.generate(),
    causation_id: opts[:causation_id],
    ip_address: opts[:ip_address],
    user_agent: opts[:user_agent]
  }

  Evoq.dispatch(command, Keyword.put(opts, :metadata, metadata))
end
```

### Idempotency

Ensure operations can be safely retried:

```elixir
defmodule MyApp.Orders.PlaceOrderV1 do
  embedded_schema do
    field :idempotency_key, :string  # Client-provided unique key
    field :order_id, :string
    field :items, {:array, :map}
  end
end

# In aggregate
def execute(%PlaceOrderV1{idempotency_key: key}, state) do
  if key in state.processed_keys do
    {:ok, []}  # Already processed - no new events
  else
    {:ok, [%OrderPlaced{...}]}
  end
end
```

## Best Practices

### 1. Events Are the Source of Truth

Never update the event store directly. All changes flow through commands
that emit events.

### 2. Keep Aggregates Small

Large aggregates with many events are slow to load. Consider splitting:

```
# Instead of one huge Order aggregate
Order (100+ events over lifetime)

# Split into focused aggregates
OrderPlacement (2-3 events)
OrderPayment (2-3 events)
OrderFulfillment (3-5 events)
```

### 3. Design Events for the Future

Include enough context to be useful without loading other data:

```elixir
# Good: Self-contained event
%OrderPlaced{
  order_id: "123",
  customer_id: "456",
  customer_email: "user@example.com",  # Denormalized
  customer_name: "John Doe",           # Denormalized
  items: [%{product_id: "p1", name: "Widget", price: 10.00}]
}

# Bad: Requires lookups
%OrderPlaced{
  order_id: "123",
  customer_id: "456",  # Have to load customer to get email
  item_ids: ["p1"]     # Have to load products to get names
}
```

### 4. Handle Event Ordering

Events within a stream are ordered, but events across streams may arrive
out of order. Design projections to handle this:

```elixir
def handle(%OrderShipped{order_id: id}, _) do
  case Repo.get(Order, id) do
    nil ->
      # Order hasn't been projected yet - retry later
      {:retry, :order_not_found}

    order ->
      # Update the order
      {:ok, _} = Repo.update(Order.changeset(order, %{status: "shipped"}))
      :ok
  end
end
```

### 5. Test Aggregates in Isolation

Aggregates are pure functions - test them without infrastructure:

```elixir
test "cannot ship unpaid order" do
  state = %Aggregate{status: :pending}
  command = %ShipOrderV1{order_id: "123"}

  assert {:error, :payment_required} = Aggregate.execute(command, state)
end
```

## Next Steps

- [Architecture Guide](architecture.md) - See how event sourcing fits in
- [Mesh Networking Guide](mesh-networking.md) - Distribute events across nodes
- [Getting Started](getting-started.md) - Build your first app
