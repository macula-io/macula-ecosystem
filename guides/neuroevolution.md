# Neuroevolution Guide

This guide covers the Macula neuroevolution stack - a framework for evolving
neural network topologies using genetic algorithms.

## Overview

The neuroevolution layer provides:

- **TWEANN** - Topology and Weight Evolving Artificial Neural Networks
- **NEAT** - NeuroEvolution of Augmenting Topologies
- **HyperNEAT** - Indirect encoding via CPPNs
- **Population management** - Speciation, selection, and reproduction

## Packages

### macula_tweann

Low-level neural network primitives:

- **Neurons** - Activation functions and connectivity
- **Substrates** - Spatial neural patterns
- **Plasticity** - Hebbian learning and neuromodulation

### macula_neuroevolution

High-level evolution framework:

- **Populations** - Manage evolving genomes
- **Fitness** - Evaluate network performance
- **Selection** - Choose parents for reproduction
- **Mutation** - Modify network structure and weights

## Core Concepts

### Genomes

A genome encodes a neural network's structure and weights:

```elixir
%Genome{
  id: "genome-001",
  neurons: [
    %Neuron{id: :input_1, type: :sensor},
    %Neuron{id: :input_2, type: :sensor},
    %Neuron{id: :hidden_1, type: :hidden, activation: :tanh},
    %Neuron{id: :output_1, type: :actuator}
  ],
  connections: [
    %Connection{from: :input_1, to: :hidden_1, weight: 0.5, enabled: true},
    %Connection{from: :input_2, to: :hidden_1, weight: -0.3, enabled: true},
    %Connection{from: :hidden_1, to: :output_1, weight: 0.8, enabled: true}
  ]
}
```

### Phenotypes

A phenotype is the instantiated neural network:

```elixir
# Convert genome to runnable network
{:ok, phenotype} = MaculaTweann.Phenotype.from_genome(genome)

# Activate with inputs
outputs = MaculaTweann.Phenotype.activate(phenotype, [0.5, 0.8])
# => [0.42]
```

### Populations

A population is a collection of evolving genomes:

```elixir
# Create initial population
{:ok, population} = MaculaNeuroevolution.Population.new(
  size: 150,
  inputs: 2,
  outputs: 1,
  fitness_fn: &evaluate_fitness/1
)

# Evolve for N generations
{:ok, final_population} = MaculaNeuroevolution.evolve(population, generations: 100)

# Get the best genome
best = MaculaNeuroevolution.Population.champion(final_population)
```

## Getting Started

### Installation

```elixir
# mix.exs
defp deps do
  [
    {:macula_tweann, "~> 0.2"},
    {:macula_neuroevolution, "~> 0.18"}
  ]
end
```

### Example: XOR Problem

The classic XOR problem - a network must learn XOR logic:

```elixir
defmodule XOREvolution do
  alias MaculaNeuroevolution.{Population, Config}

  def run do
    config = %Config{
      population_size: 150,
      inputs: 2,
      outputs: 1,
      fitness_threshold: 15.9,  # Max possible: 16.0
      max_generations: 300
    }

    {:ok, population} = Population.new(config, fitness_fn: &fitness/1)
    {:ok, result} = MaculaNeuroevolution.evolve(population)

    IO.puts("Solution found in #{result.generation} generations")
    result.champion
  end

  defp fitness(genome) do
    phenotype = MaculaTweann.Phenotype.from_genome(genome)

    # XOR test cases
    test_cases = [
      {[0.0, 0.0], 0.0},
      {[0.0, 1.0], 1.0},
      {[1.0, 0.0], 1.0},
      {[1.0, 1.0], 0.0}
    ]

    # Calculate fitness (closer to 16.0 is better)
    Enum.reduce(test_cases, 0.0, fn {inputs, expected}, acc ->
      [output] = MaculaTweann.Phenotype.activate(phenotype, inputs)
      error = abs(expected - output)
      acc + (4.0 - error * error)  # Squared error penalty
    end)
  end
end
```

## NEAT Algorithm

NEAT (NeuroEvolution of Augmenting Topologies) is the default algorithm:

### Key Features

1. **Historical Markings** - Track gene origins for crossover
2. **Speciation** - Protect innovation via niching
3. **Complexification** - Start minimal, add complexity

### Configuration

```elixir
%Config{
  # Population
  population_size: 150,

  # Mutation rates
  weight_mutation_rate: 0.8,
  weight_perturb_rate: 0.9,
  add_node_rate: 0.03,
  add_connection_rate: 0.05,

  # Speciation
  compatibility_threshold: 3.0,
  excess_coefficient: 1.0,
  disjoint_coefficient: 1.0,
  weight_coefficient: 0.4,

  # Selection
  survival_rate: 0.2,
  elitism: 2
}
```

### Mutations

```elixir
# Weight mutation - adjust existing weights
MaculaNeuroevolution.Mutation.mutate_weights(genome, rate: 0.8)

# Add node - split an existing connection
MaculaNeuroevolution.Mutation.add_node(genome)

# Add connection - connect previously unconnected neurons
MaculaNeuroevolution.Mutation.add_connection(genome)
```

### Crossover

```elixir
# Create offspring from two parents
{:ok, offspring} = MaculaNeuroevolution.Crossover.mate(parent1, parent2)
```

## HyperNEAT

HyperNEAT uses CPPNs (Compositional Pattern Producing Networks) to generate
large-scale neural networks with geometric regularities.

### Concept

```
┌─────────────────────────────────────────────────────────────────┐
│  CPPN (evolved by NEAT)                                         │
│  Inputs: (x1, y1, x2, y2) - coordinates of two neurons          │
│  Output: weight between those neurons                           │
├─────────────────────────────────────────────────────────────────┤
│                           │                                      │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Substrate (target network)                              │    │
│  │  ┌───┬───┬───┬───┐        ┌───┬───┬───┬───┐             │    │
│  │  │ o │ o │ o │ o │   →    │ o │ o │ o │ o │             │    │
│  │  └───┴───┴───┴───┘        └───┴───┴───┴───┘             │    │
│  │  Input layer              Hidden layer                   │    │
│  │                                                          │    │
│  │  CPPN queries: "What's the weight from (0,0) to (0.5,1)?"│    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Usage

```elixir
# Define substrate geometry
substrate = %Substrate{
  input_layer: [{-1, -1}, {0, -1}, {1, -1}],
  hidden_layers: [
    [{-0.5, 0}, {0.5, 0}]
  ],
  output_layer: [{0, 1}]
}

# Evolve CPPN
{:ok, cppn} = MaculaNeuroevolution.HyperNEAT.evolve(
  substrate: substrate,
  fitness_fn: &task_fitness/1
)

# Generate substrate network from CPPN
{:ok, network} = MaculaNeuroevolution.HyperNEAT.develop(cppn, substrate)
```

## Distributed Evolution

The neuroevolution framework integrates with the Macula mesh for
distributed fitness evaluation:

### Parallel Fitness Evaluation

```elixir
defmodule DistributedEvolution do
  def evaluate_population(population) do
    # Distribute fitness evaluation across mesh
    population.genomes
    |> Enum.map(fn genome ->
      Task.async(fn ->
        # This could run on any node in the mesh
        :macula.call(client, "io.myapp.evaluate_genome", %{genome: genome})
      end)
    end)
    |> Enum.map(&Task.await/1)
  end
end
```

### Island Model

Run multiple populations on different nodes with periodic migration:

```elixir
defmodule IslandEvolution do
  def run(num_islands) do
    # Start islands on different mesh nodes
    islands = for i <- 1..num_islands do
      {:ok, pid} = :macula.call(client, "io.myapp.start_island", %{
        island_id: i,
        config: island_config()
      })
      pid
    end

    # Periodic migration
    migrate_loop(islands, migration_interval: 10)
  end

  defp migrate_loop(islands, opts) do
    Process.sleep(opts[:migration_interval] * 1000)

    # Exchange best genomes between adjacent islands
    for {island, next} <- Enum.zip(islands, tl(islands) ++ [hd(islands)]) do
      best = :macula.call(client, "io.myapp.get_champion", %{island: island})
      :macula.call(client, "io.myapp.inject_genome", %{island: next, genome: best})
    end

    migrate_loop(islands, opts)
  end
end
```

## Advanced Topics

### Custom Activation Functions

```elixir
defmodule MyActivations do
  def swish(x), do: x * :math.tanh(:math.log(1 + :math.exp(x)))

  def gaussian(x), do: :math.exp(-x * x)
end

# Register custom activation
MaculaTweann.Activation.register(:swish, &MyActivations.swish/1)
```

### Neuromodulation

Networks that can modify their own learning:

```elixir
%Neuron{
  id: :modulator_1,
  type: :modulator,
  activation: :tanh,
  targets: [:hidden_1, :hidden_2],  # Neurons this modulates
  modulation_type: :learning_rate   # What it modulates
}
```

### Novelty Search

Instead of optimizing fitness, search for novel behaviors:

```elixir
{:ok, population} = MaculaNeuroevolution.NoveltySearch.evolve(
  initial_population: population,
  behavior_fn: &extract_behavior/1,
  archive_threshold: 0.1
)

defp extract_behavior(genome) do
  # Return a behavior vector (e.g., final positions, action sequence)
  phenotype = MaculaTweann.Phenotype.from_genome(genome)
  simulate_and_record(phenotype)
end
```

## Use Cases

### Game AI

Evolve agents that play games:

```elixir
defp fitness(genome) do
  phenotype = MaculaTweann.Phenotype.from_genome(genome)

  # Play 10 games, average score
  scores = for _ <- 1..10 do
    play_game(phenotype)
  end

  Enum.sum(scores) / length(scores)
end
```

### Robot Control

Evolve controllers for simulated robots:

```elixir
defp fitness(genome) do
  phenotype = MaculaTweann.Phenotype.from_genome(genome)

  # Simulate robot for 1000 timesteps
  final_state = Enum.reduce(1..1000, initial_state, fn _, state ->
    sensors = read_sensors(state)
    actions = MaculaTweann.Phenotype.activate(phenotype, sensors)
    apply_actions(state, actions)
  end)

  # Fitness = distance traveled
  distance(initial_state.position, final_state.position)
end
```

### Adaptive Systems

Evolve systems that adapt to changing conditions:

```elixir
defmodule AdaptiveController do
  use GenServer

  def handle_info(:evolve, state) do
    # Periodically evolve based on recent performance
    recent_fitness = calculate_recent_fitness(state.history)

    if recent_fitness < state.threshold do
      # Performance dropped - evolve new controller
      {:ok, new_genome} = MaculaNeuroevolution.evolve_from(
        state.current_genome,
        fitness_fn: &current_environment_fitness/1,
        generations: 10
      )
      {:noreply, %{state | current_genome: new_genome}}
    else
      {:noreply, state}
    end
  end
end
```

## Best Practices

### 1. Start Simple

Begin with minimal networks and let evolution add complexity:

```elixir
%Config{
  initial_connection_density: 0.5,  # Not fully connected
  add_node_rate: 0.03,              # Low rate of adding nodes
  add_connection_rate: 0.05         # Low rate of adding connections
}
```

### 2. Design Good Fitness Functions

Fitness should be:
- **Smooth** - Small improvements should be rewarded
- **Incremental** - Partial solutions get partial credit
- **Fast** - You'll evaluate millions of networks

```elixir
# Good: Smooth gradient
defp fitness(genome) do
  distance_to_goal + time_bonus + efficiency_bonus
end

# Bad: Binary
defp fitness(genome) do
  if reached_goal?, do: 1.0, else: 0.0
end
```

### 3. Use Appropriate Population Sizes

- **Simple problems**: 50-150 genomes
- **Complex problems**: 500-1000+ genomes
- **HyperNEAT**: 100-500 CPPNs

### 4. Monitor Evolution

Track metrics to understand what's happening:

```elixir
MaculaNeuroevolution.evolve(population,
  callbacks: [
    on_generation: fn gen, pop ->
      IO.puts("Gen #{gen}: best=#{pop.best_fitness}, avg=#{pop.avg_fitness}, species=#{length(pop.species)}")
    end
  ]
)
```

## Next Steps

- [Architecture Guide](architecture.md) - See how neuroevolution fits in
- [Mesh Networking Guide](mesh-networking.md) - Distributed evolution
- [Getting Started](getting-started.md) - Build your first app
