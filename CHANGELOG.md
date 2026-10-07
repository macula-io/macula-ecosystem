# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The repository now holds one generated document, `FEATURES.md`: what Macula does today, built by
  `scripts/generate_features.py` from released tags, README feature sections verified against the files they name,
  and the security register's public export. It regenerates by pull request; nothing merges automatically
  (macula-ecosystem#1).
- README rewritten: the mental model, how the document is made, and where everything else lives.

### Added

- `scripts/generate_features.py` with tests, `features/sources.json`, `scripts/md_to_pdf.sh`.
- Workflows `features` (regenerate and propose) and `test`.

### Removed

- The hand-written guides (overview, architecture, getting started, event sourcing, neuroevolution, content transfer)
  and their diagrams: every API sample in them no longer matched the released code.

## [0.1.0] - 2026-01-08

### Added

- Initial release of the Macula Ecosystem documentation hub
- Comprehensive guides:
  - Overview - Introduction to the ecosystem
  - Architecture - System design and data flow
  - Getting Started - First application tutorial
  - Event Sourcing - CQRS/ES patterns with ReckonDB + Evoq
  - Mesh Networking - Macula HTTP/3 mesh guide
  - Neuroevolution - TWEANN and NEAT algorithms
  - MaculaOS - Edge node operating system
- Professional SVG artwork:
  - `ecosystem-overview.svg` - Master architecture diagram
  - `data-flow.svg` - Event-sourced application data flow
  - `logo.svg` - Ecosystem logo
- `MaculaEcosystem` module with:
  - `version/0` - Package version
  - `packages/0` - Ecosystem package registry

### Infrastructure Layer (reckon-db-org)

Documentation for:
- **reckon_db** - BEAM-native event store
- **reckon_gater** - Event store gateway
- **evoq** - Event sourcing primitives
- **reckon_evoq** - Evoq + ReckonDB adapter

### Application Layer (macula-io)

Documentation for:
- **macula** - HTTP/3 mesh networking
- **macula_tweann** - TWEANN neural networks
- **macula_neuroevolution** - Neuroevolution framework
- **macula_console** - Management console
- **macula_os** - Edge operating system

[0.1.0]: https://github.com/macula-io/macula-ecosystem/releases/tag/v0.1.0
