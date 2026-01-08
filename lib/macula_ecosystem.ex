defmodule MaculaEcosystem do
  @moduledoc """
  Documentation hub for the Macula distributed application platform.

  The Macula ecosystem consists of two complementary organizations:

  ## Infrastructure Layer (reckon-db-org)

  Event sourcing and persistence infrastructure:

  | Package | Description | Links |
  |---------|-------------|-------|
  | **reckon_db** | BEAM-native event store built on Khepri/Ra | [GitHub](https://github.com/reckon-db-org/reckon-db) \\| [HexDocs](https://hexdocs.pm/reckon_db) |
  | **reckon_gater** | Gateway for distributed event store access | [GitHub](https://github.com/reckon-db-org/reckon-gater) \\| [HexDocs](https://hexdocs.pm/reckon_gater) |
  | **evoq** | Event sourcing primitives (aggregates, commands, events) | [GitHub](https://github.com/reckon-db-org/evoq) \\| [HexDocs](https://hexdocs.pm/evoq) |
  | **reckon_evoq** | Adapter connecting Evoq to ReckonDB | [GitHub](https://github.com/reckon-db-org/reckon-evoq) \\| [HexDocs](https://hexdocs.pm/reckon_evoq) |

  ## Application Layer (macula-io)

  Distributed application platform and tools:

  | Package | Description | Links |
  |---------|-------------|-------|
  | **macula** | HTTP/3 mesh networking over QUIC | [GitHub](https://github.com/macula-io/macula) \\| [HexDocs](https://hexdocs.pm/macula) |
  | **macula_tweann** | TWEANN neural network topologies | [GitHub](https://github.com/macula-io/macula-tweann) \\| [HexDocs](https://hexdocs.pm/macula_tweann) |
  | **macula_neuroevolution** | Neuroevolution framework | [GitHub](https://github.com/macula-io/macula-neuroevolution) \\| [HexDocs](https://hexdocs.pm/macula_neuroevolution) |
  | **macula_console** | Management console for Macula platform | [GitHub](https://github.com/macula-io/macula-console) |
  | **macula_os** | Edge node operating system | [GitHub](https://github.com/macula-io/macula-os) |

  ## Getting Started

  See the [Overview Guide](overview.html) for an introduction to the ecosystem,
  or jump directly to:

  - [Architecture](architecture.html) - How the pieces fit together
  - [Getting Started](getting-started.html) - Build your first app
  - [Event Sourcing](event-sourcing.html) - Using ReckonDB + Evoq
  - [Mesh Networking](mesh-networking.html) - Using Macula mesh
  - [Neuroevolution](neuroevolution.html) - AI/ML capabilities
  - [MaculaOS](macula-os.html) - Edge deployment
  """

  @doc """
  Returns the current version of the macula_ecosystem package.
  """
  @spec version() :: String.t()
  def version, do: "0.1.0"

  @doc """
  Returns a map of all ecosystem packages with their hex.pm names and descriptions.
  """
  @spec packages() :: map()
  def packages do
    %{
      infrastructure: [
        %{name: :reckon_db, description: "BEAM-native event store", hex: "reckon_db"},
        %{name: :reckon_gater, description: "Event store gateway", hex: "reckon_gater"},
        %{name: :evoq, description: "Event sourcing primitives", hex: "evoq"},
        %{name: :reckon_evoq, description: "Evoq + ReckonDB adapter", hex: "reckon_evoq"}
      ],
      application: [
        %{name: :macula, description: "HTTP/3 mesh networking", hex: "macula"},
        %{name: :macula_tweann, description: "TWEANN neural networks", hex: "macula_tweann"},
        %{name: :macula_neuroevolution, description: "Neuroevolution framework", hex: "macula_neuroevolution"}
      ],
      tools: [
        %{name: :macula_console, description: "Management console", hex: nil},
        %{name: :macula_os, description: "Edge operating system", hex: nil}
      ]
    }
  end
end
