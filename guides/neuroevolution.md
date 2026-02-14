# Neuroevolution Guide

> **Note:** The neuroevolution packages have moved to the **Faber ecosystem** under
> [rgfaber](https://github.com/rgfaber). The packages are now published as
> [`faber_tweann`](https://hexdocs.pm/faber_tweann) and
> [`faber_neuroevolution`](https://hexdocs.pm/faber_neuroevolution) on hex.pm.
>
> See [faber-ecosystem](https://github.com/rgfaber/faber-ecosystem) for full documentation.

This guide covers the neuroevolution stack - a framework for evolving
neural network topologies using genetic algorithms.

## Overview

The neuroevolution layer provides:

- **TWEANN** - Topology and Weight Evolving Artificial Neural Networks
- **NEAT** - NeuroEvolution of Augmenting Topologies
- **HyperNEAT** - Indirect encoding via CPPNs
- **Population management** - Speciation, selection, and reproduction

## Packages

### faber_tweann

Low-level neural network primitives:

- **Neurons** - Activation functions and connectivity
- **Substrates** - Spatial neural patterns
- **Plasticity** - Hebbian learning and neuromodulation

### faber_neuroevolution

High-level evolution framework:

- **Populations** - Manage evolving genomes
- **Fitness** - Evaluate network performance
- **Selection** - Choose parents for reproduction
- **Mutation** - Modify network structure and weights

## Core Concepts

### Genomes

A genome encodes a neural network's structure and weights. The Faber
libraries are Erlang-native; the conceptual examples below illustrate the
data structures:

```erlang
%% A genome is a genotype record containing neurons and connections
Genome = #{
    id => <<"genome-001">>,
    neurons => [
        #{id => input_1, type => sensor},
        #{id => input_2, type => sensor},
        #{id => hidden_1, type => hidden, activation => tanh},
        #{id => output_1, type => actuator}
    ],
    connections => [
        #{from => input_1, to => hidden_1, weight => 0.5, enabled => true},
        #{from => input_2, to => hidden_1, weight => -0.3, enabled => true},
        #{from => hidden_1, to => output_1, weight => 0.8, enabled => true}
    ]
}.
```

### Phenotypes

A phenotype is the instantiated neural network:

```erlang
%% Convert genome to runnable network
Phenotype = faber_tweann_phenotype:from_genotype(Genome),

%% Activate with inputs
Outputs = faber_tweann_phenotype:activate(Phenotype, [0.5, 0.8]).
%% => [0.42]
```

### Populations

A population is a collection of evolving genomes:

```erlang
%% Create initial population
{ok, Population} = faber_neuroevolution:population_new(#{
    size => 150,
    inputs => 2,
    outputs => 1,
    fitness_fn => fun evaluate_fitness/1
}),

%% Evolve for N generations
{ok, FinalPopulation} = faber_neuroevolution:evolve(Population, #{generations => 100}),

%% Get the best genome
Best = faber_neuroevolution:champion(FinalPopulation).
```

## Getting Started

### Installation (Erlang)

```erlang
%% rebar.config
{deps, [
    {faber_tweann, "~> 0.1.0"},
    {faber_neuroevolution, "~> 0.1.0"}
]}.
```

### Installation (Elixir)

```elixir
# mix.exs
defp deps do
  [
    {:faber_tweann, "~> 0.1.0"},
    {:faber_neuroevolution, "~> 0.1.0"}
  ]
end
```

### Example: XOR Problem

The classic XOR problem - a network must learn XOR logic:

```erlang
-module(xor_evolution).
-export([run/0]).

run() ->
    Config = #{
        population_size => 150,
        inputs => 2,
        outputs => 1,
        fitness_threshold => 15.9,  %% Max possible: 16.0
        max_generations => 300
    },
    {ok, Population} = faber_neuroevolution:population_new(Config, #{
        fitness_fn => fun fitness/1
    }),
    {ok, Result} = faber_neuroevolution:evolve(Population),
    io:format("Solution found in ~p generations~n", [maps:get(generation, Result)]),
    maps:get(champion, Result).

fitness(Genome) ->
    Phenotype = faber_tweann_phenotype:from_genotype(Genome),
    TestCases = [
        {[0.0, 0.0], 0.0},
        {[0.0, 1.0], 1.0},
        {[1.0, 0.0], 1.0},
        {[1.0, 1.0], 0.0}
    ],
    lists:foldl(fun({Inputs, Expected}, Acc) ->
        [Output] = faber_tweann_phenotype:activate(Phenotype, Inputs),
        Error = abs(Expected - Output),
        Acc + (4.0 - Error * Error)
    end, 0.0, TestCases).
```

## NEAT Algorithm

NEAT (NeuroEvolution of Augmenting Topologies) is the default algorithm:

### Key Features

1. **Historical Markings** - Track gene origins for crossover
2. **Speciation** - Protect innovation via niching
3. **Complexification** - Start minimal, add complexity

### Configuration

```erlang
Config = #{
    %% Population
    population_size => 150,

    %% Mutation rates
    weight_mutation_rate => 0.8,
    weight_perturb_rate => 0.9,
    add_node_rate => 0.03,
    add_connection_rate => 0.05,

    %% Speciation
    compatibility_threshold => 3.0,
    excess_coefficient => 1.0,
    disjoint_coefficient => 1.0,
    weight_coefficient => 0.4,

    %% Selection
    survival_rate => 0.2,
    elitism => 2
}.
```

## HyperNEAT

HyperNEAT uses CPPNs (Compositional Pattern Producing Networks) to generate
large-scale neural networks with geometric regularities.

### Concept

```
+------------------------------------------------------------------+
|  CPPN (evolved by NEAT)                                          |
|  Inputs: (x1, y1, x2, y2) - coordinates of two neurons          |
|  Output: weight between those neurons                            |
+------------------------------------------------------------------+
|                           |                                      |
|                           v                                      |
|  +-------------------------------------------------------+      |
|  |  Substrate (target network)                            |      |
|  |  +---+---+---+---+        +---+---+---+---+           |      |
|  |  | o | o | o | o |   ->   | o | o | o | o |           |      |
|  |  +---+---+---+---+        +---+---+---+---+           |      |
|  |  Input layer              Hidden layer                 |      |
|  |                                                        |      |
|  |  CPPN queries: "What's the weight from (0,0) to       |      |
|  |  (0.5,1)?"                                             |      |
|  +-------------------------------------------------------+      |
+------------------------------------------------------------------+
```

## Distributed Evolution

The neuroevolution framework can optionally integrate with the Macula mesh
for distributed fitness evaluation:

### Parallel Fitness Evaluation

```erlang
evaluate_population(Client, Population) ->
    %% Distribute fitness evaluation across mesh
    Pids = lists:map(fun(Genome) ->
        spawn_link(fun() ->
            Result = macula:call(Client, <<"io.myapp.evaluate_genome">>,
                                 #{genome => Genome}),
            self() ! {genome_result, Genome, Result}
        end)
    end, maps:get(genomes, Population)),
    collect_results(Pids).
```

### Island Model

Run multiple populations on different nodes with periodic migration:

```erlang
run_islands(Client, NumIslands) ->
    %% Start islands on different mesh nodes
    Islands = lists:map(fun(I) ->
        {ok, Pid} = macula:call(Client, <<"io.myapp.start_island">>,
                                #{island_id => I, config => island_config()}),
        Pid
    end, lists:seq(1, NumIslands)),

    %% Periodic migration
    migrate_loop(Client, Islands, #{migration_interval => 10}).
```

## Best Practices

### 1. Start Simple

Begin with minimal networks and let evolution add complexity.

### 2. Design Good Fitness Functions

Fitness should be:
- **Smooth** - Small improvements should be rewarded
- **Incremental** - Partial solutions get partial credit
- **Fast** - You'll evaluate millions of networks

### 3. Use Appropriate Population Sizes

- **Simple problems**: 50-150 genomes
- **Complex problems**: 500-1000+ genomes
- **HyperNEAT**: 100-500 CPPNs

## Next Steps

- [Faber Ecosystem](https://github.com/rgfaber/faber-ecosystem) - Full Faber documentation
- [faber_tweann on HexDocs](https://hexdocs.pm/faber_tweann) - API reference
- [faber_neuroevolution on HexDocs](https://hexdocs.pm/faber_neuroevolution) - API reference
- [Architecture Guide](architecture.md) - See how neuroevolution fits in
- [Mesh Networking Guide](mesh-networking.md) - Distributed evolution via Macula
- [Getting Started](getting-started.md) - Build your first app
