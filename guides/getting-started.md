# Getting Started

This guide walks you through building your first event-sourced application
on the Macula ecosystem.

## Prerequisites

- **Erlang/OTP 26+** - The BEAM runtime
- **Elixir 1.15+** - For application development
- **Docker** (optional) - For running ReckonDB cluster

## Installation

Add the required packages to your `mix.exs`:

```elixir
defp deps do
  [
    # Event sourcing
    {:evoq, "~> 1.0"},
    {:reckon_evoq, "~> 1.0"},

    # For direct event store access (optional)
    {:reckon_db, "~> 1.0"},
    {:reckon_gater, "~> 1.0"},

    # Mesh networking (optional)
    {:macula, "~> 0.17"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Project Structure

We recommend organizing your application using vertical slicing:

```
lib/
├── my_app/
│   ├── orders/                    # Domain: Orders
│   │   ├── aggregate.ex           # Order aggregate
│   │   ├── place_order/           # Command slice
│   │   │   ├── place_order_v1.ex  # Command struct
│   │   │   ├── maybe_place.ex     # Command handler
│   │   │   └── order_placed.ex    # Event struct
│   │   ├── ship_order/            # Another command slice
│   │   │   ├── ship_order_v1.ex
│   │   │   ├── maybe_ship.ex
│   │   │   └── order_shipped.ex
│   │   └── projections/           # Read model updates
│   │       └── order_placed_to_orders.ex
│   │
│   ├── inventory/                 # Domain: Inventory
│   │   └── ...
│   │
│   └── read_models/               # Query-optimized tables
│       ├── order.ex
│       └── inventory_item.ex
│
└── my_app_web/                    # Phoenix web layer
    └── live/
        └── orders_live.ex
```

## Step 1: Define Your Domain

### Events First

Start by defining the events that matter to your business:

```elixir
# lib/my_app/orders/place_order/order_placed.ex
defmodule MyApp.Orders.OrderPlaced do
  @moduledoc "An order was placed by a customer."

  use Evoq.Event

  embedded_schema do
    field :order_id, :string
    field :customer_id, :string
    field :items, {:array, :map}
    field :total_amount, :decimal
    field :placed_at, :utc_datetime
  end
end
```

### Commands

Define commands as structs with validation:

```elixir
# lib/my_app/orders/place_order/place_order_v1.ex
defmodule MyApp.Orders.PlaceOrderV1 do
  @moduledoc "Place a new order."

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
    |> validate_length(:items, min: 1)
  end
end
```

### Aggregate

The aggregate contains your business rules:

```elixir
# lib/my_app/orders/aggregate.ex
defmodule MyApp.Orders.Aggregate do
  @moduledoc "Order aggregate - enforces business rules."

  use Evoq.Aggregate

  alias MyApp.Orders.{PlaceOrderV1, OrderPlaced}
  alias MyApp.Orders.{ShipOrderV1, OrderShipped}

  defstruct [:order_id, :status, :items, :total_amount]

  # Command handlers return events
  def execute(%PlaceOrderV1{} = cmd, nil) do
    # New order - no existing state
    {:ok, [
      %OrderPlaced{
        order_id: cmd.order_id,
        customer_id: cmd.customer_id,
        items: cmd.items,
        total_amount: calculate_total(cmd.items),
        placed_at: DateTime.utc_now()
      }
    ]}
  end

  def execute(%PlaceOrderV1{}, %{status: _}) do
    {:error, :order_already_exists}
  end

  def execute(%ShipOrderV1{} = cmd, %{status: :placed} = state) do
    {:ok, [
      %OrderShipped{
        order_id: cmd.order_id,
        shipped_at: DateTime.utc_now(),
        tracking_number: cmd.tracking_number
      }
    ]}
  end

  def execute(%ShipOrderV1{}, %{status: status}) do
    {:error, {:invalid_status, status}}
  end

  # Event handlers update state
  def apply(%OrderPlaced{} = event, _state) do
    %__MODULE__{
      order_id: event.order_id,
      status: :placed,
      items: event.items,
      total_amount: event.total_amount
    }
  end

  def apply(%OrderShipped{}, state) do
    %{state | status: :shipped}
  end

  defp calculate_total(items) do
    Enum.reduce(items, Decimal.new(0), fn item, acc ->
      Decimal.add(acc, Decimal.mult(item.price, item.quantity))
    end)
  end
end
```

## Step 2: Configure the Event Store

Add configuration for ReckonEvoq:

```elixir
# config/config.exs
config :evoq,
  event_store: ReckonEvoq.EventStore

config :reckon_evoq,
  stores: [
    default: [
      nodes: ["reckon@127.0.0.1"],
      pool_size: 10
    ]
  ]
```

For development, you can run ReckonDB locally:

```bash
# Start a single-node ReckonDB for development
docker run -d \
  --name reckon-dev \
  -p 4369:4369 \
  -p 9100:9100 \
  reckondb/reckon_db:latest
```

## Step 3: Create Projections

Projections update read models when events occur:

```elixir
# lib/my_app/orders/projections/order_placed_to_orders.ex
defmodule MyApp.Orders.Projections.OrderPlacedToOrders do
  @moduledoc "Updates the orders read model when an order is placed."

  use Evoq.Projection

  alias MyApp.Orders.OrderPlaced
  alias MyApp.ReadModels.Order

  def handle(%OrderPlaced{} = event, _metadata) do
    %Order{}
    |> Order.changeset(%{
      id: event.order_id,
      customer_id: event.customer_id,
      items: event.items,
      total_amount: event.total_amount,
      status: "placed",
      placed_at: event.placed_at
    })
    |> MyApp.Repo.insert!(
      on_conflict: :replace_all,
      conflict_target: :id
    )

    :ok
  end
end
```

### Read Model

Define your read model optimized for queries:

```elixir
# lib/my_app/read_models/order.ex
defmodule MyApp.ReadModels.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "orders" do
    field :customer_id, :string
    field :items, {:array, :map}
    field :total_amount, :decimal
    field :status, :string
    field :placed_at, :utc_datetime
    field :shipped_at, :utc_datetime

    timestamps()
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:id, :customer_id, :items, :total_amount, :status, :placed_at, :shipped_at])
  end
end
```

## Step 4: Dispatch Commands

Use the Evoq application to dispatch commands:

```elixir
# In your Phoenix controller or LiveView
def handle_event("place_order", params, socket) do
  command = %MyApp.Orders.PlaceOrderV1{
    order_id: Ecto.UUID.generate(),
    customer_id: socket.assigns.current_user.id,
    items: params["items"]
  }

  case Evoq.dispatch(command, aggregate: MyApp.Orders.Aggregate) do
    {:ok, events} ->
      {:noreply, put_flash(socket, :info, "Order placed!")}

    {:error, :order_already_exists} ->
      {:noreply, put_flash(socket, :error, "Order already exists")}

    {:error, changeset} ->
      {:noreply, assign(socket, :changeset, changeset)}
  end
end
```

## Step 5: Query Read Models

Query your read models directly - they're optimized for fast retrieval:

```elixir
# Simple queries - no joins needed
def list_orders_for_customer(customer_id) do
  Order
  |> where([o], o.customer_id == ^customer_id)
  |> order_by([o], desc: o.placed_at)
  |> Repo.all()
end

def get_order(order_id) do
  Repo.get(Order, order_id)
end
```

## Step 6: Add Mesh Networking (Optional)

To enable distributed communication via the Macula mesh:

```elixir
# config/config.exs
config :macula,
  realm: "io.myapp",
  bootstrap_nodes: ["macula.io:4433"]
```

### Advertise Services

```elixir
# In your application startup
defmodule MyApp.Services do
  def start_link(_) do
    # Connect to mesh
    {:ok, client} = :macula.connect(realm: "io.myapp")

    # Advertise RPC endpoints
    :macula.advertise(client, "io.myapp.orders.get", &get_order/1)
    :macula.advertise(client, "io.myapp.orders.place", &place_order/1)

    {:ok, client}
  end

  def get_order(%{order_id: id}) do
    case MyApp.get_order(id) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  end

  def place_order(params) do
    # ... dispatch command
  end
end
```

### Call Remote Services

```elixir
# Call a service on any node in the mesh
{:ok, order} = :macula.call(client, "io.myapp.orders.get", %{order_id: "123"})
```

### Subscribe to Events

```elixir
# Subscribe to domain events across the mesh
:macula.subscribe(client, "io.myapp.orders.order_placed", fn event ->
  IO.inspect(event, label: "Order placed on mesh")
end)
```

## Testing

### Unit Testing Aggregates

```elixir
defmodule MyApp.Orders.AggregateTest do
  use ExUnit.Case

  alias MyApp.Orders.{Aggregate, PlaceOrderV1, OrderPlaced}

  describe "place_order" do
    test "places a new order" do
      cmd = %PlaceOrderV1{
        order_id: "order-1",
        customer_id: "customer-1",
        items: [%{product_id: "p1", quantity: 2, price: Decimal.new("10.00")}]
      }

      assert {:ok, [%OrderPlaced{} = event]} = Aggregate.execute(cmd, nil)
      assert event.order_id == "order-1"
      assert event.total_amount == Decimal.new("20.00")
    end

    test "rejects duplicate order" do
      cmd = %PlaceOrderV1{order_id: "order-1", customer_id: "c1", items: []}
      state = %Aggregate{order_id: "order-1", status: :placed}

      assert {:error, :order_already_exists} = Aggregate.execute(cmd, state)
    end
  end
end
```

### Integration Testing

```elixir
defmodule MyApp.Orders.IntegrationTest do
  use MyApp.DataCase

  test "full order lifecycle" do
    # Place order
    {:ok, _} = Evoq.dispatch(%PlaceOrderV1{...}, aggregate: Aggregate)

    # Verify projection updated
    assert order = Repo.get(Order, "order-1")
    assert order.status == "placed"

    # Ship order
    {:ok, _} = Evoq.dispatch(%ShipOrderV1{...}, aggregate: Aggregate)

    # Verify updated
    order = Repo.get(Order, "order-1")
    assert order.status == "shipped"
  end
end
```

## Next Steps

- [Event Sourcing Guide](event-sourcing.md) - Advanced patterns and best practices
- [Mesh Networking Guide](mesh-networking.md) - Distributed communication
- [Architecture Guide](architecture.md) - Understanding the full stack

## Troubleshooting

### Events Not Persisting

1. Check ReckonDB is running: `docker ps | grep reckon`
2. Verify connection config in `config/config.exs`
3. Check logs: `docker logs reckon-dev`

### Projections Not Updating

1. Ensure projection is registered in your application supervisor
2. Check subscription is active
3. Verify event type matches projection handler

### Mesh Connection Issues

1. Check firewall allows QUIC (UDP 4433)
2. Verify realm configuration matches
3. Check bootstrap nodes are reachable
