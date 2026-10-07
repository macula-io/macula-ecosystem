# Macula Ecosystem

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

<p align="center">
  <img src="assets/logo.svg" width="120" height="120" alt="Macula">
</p>

This repository exists so anyone (a partner, a funder, a new contributor) can read one current technical document of
what Macula does today: **[FEATURES.md](FEATURES.md)**. It is generated from released code and from the security
register's public edition, so it states nothing those sources do not. Do not edit it by hand.

## The mental model

Macula separates the substrate, the infrastructure, identity and the clients, each in its own repository, using a
railroad analogy:

| Railroad role | Macula role | Implementation |
|---|---|---|
| **The track** | Peering protocol (QUIC, mesh routing) | `macula` (the SDK and protocol) |
| **The station** | Infrastructure node (DHT participation, SWIM liveness, routing, bootstrap) | `macula-station` |
| **The train company** | Identity and membership (who is a member of which realm) | `macula-realm` |
| **The passenger's ticket** | Client SDK that holds capabilities | the SDKs, consumed by application processes |
| **The passenger** | Application process | services, the command-line tool, the MCP server and other outbound-only clients |

Stations are realm-agnostic: one station can serve several realms. Realm membership is held by the realm service, not by
the station.

## How FEATURES.md is made

`scripts/generate_features.py` builds it from three sources and nothing else:

1. **Components**: the highest released semver tag of each repository listed in
   [`features/sources.json`](features/sources.json), or of its public image where the source is private.
2. **Capabilities**: the section between `<!-- features:start -->` and `<!-- features:end -->` in each repository's
   README at that released tag. Every bullet names, in backticks, a file that exists at the tag; a bullet that does not
   stops the build.
3. **Security**: `data/security_register.json`, the public (TLP:CLEAR) export of the security register, delivered by
   the register's own CI. It is quoted exactly, and refused unless the register's live evaluator was green on that same
   register commit.

The build also refuses any output that matches a denylist held as a repository secret.

It regenerates when the register delivers a new export (branch `register-export`), nightly (new releases), and on
demand. A run that changes the document pushes it to a branch (`register-export` or `features-update`); it never opens
or merges a pull request. A member of the Macula team opens the pull request from that branch, and a maintainer
merges it. Nothing merges automatically.

To have a repository's capabilities appear, add a feature section to its README:

```markdown
<!-- features:start -->
- Calls a procedure on any provider in the realm (`src/macula.erl`)
<!-- features:end -->
```

It is read at the next released tag.

## Where everything else lives

- Each SDK and service: its own README and `docs/`.
- Joining a realm: [guides/joining-a-realm.md](guides/joining-a-realm.md).
- Reporting a vulnerability: [SECURITY.md](SECURITY.md).
- Event sourcing (Reckon): [reckon-db-org/reckon-ecosystem](https://github.com/reckon-db-org/reckon-ecosystem).
- Neuroevolution (Faber): [rgfaber/faber-ecosystem](https://github.com/rgfaber/faber-ecosystem).

## License

Apache 2.0. See [LICENSE](LICENSE).
