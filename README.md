# Bun foundation

See the [Bun baseline](docs/developer/bun-baseline.md) for the language-specific
toolchain, task surface, test tiers, coverage ledgers, build, and maintenance
boundary. TypeScript variants accompany the shared standards for
[date/time](docs/standards/datetime/languages/typescript.md),
[domain-driven design](docs/standards/domain-driven-design/languages/typescript.md),
[functional practices](docs/standards/functional-practices/languages/typescript.md),
[SOLID](docs/standards/solid-principles/languages/typescript.md),
[stateless OOP/DI](docs/standards/stateless-oop-di/languages/typescript.md),
[testing](docs/standards/testing/languages/typescript.md),
[utilities](docs/standards/utilities/languages/typescript.md), and
[validation](docs/standards/validation/languages/typescript.md).

## Library package

`@atomicloud/diene.config` is the config-loading engine for the AtomiCloud
TypeScript family: a 4-tier merge (base YAML → landscape overlay → build-time →
runtime env), zod validation of the final layer, and `$schema` generation.
Shipped as dual **ESM + CommonJS** with bundled types and three entry points:
the package root, `/build-time` and `/test-helper`.

See the [config standard](docs/standards/config/index.md) for the contract and
the [npm release runbook](docs/developer/npm-release.md) for publishing.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.config)](https://www.npmjs.com/package/@atomicloud/diene.config)
[![CI](https://github.com/AtomiCloud/diene.bun-config/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-config/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.config
```

### Usage

```ts
import { ConfigLoader, ConfigRegistry, YamlConfigSource } from '@atomicloud/diene.config';
import { z } from 'zod';

const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
const config = await new ConfigLoader(new YamlConfigSource({ dir: 'config' }), registry, { prefix: 'ATOMI_' }).load();
config.get('server').port;
```

# Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml), whose `includes:` block maps each
namespace to a file under [`tasks/`](tasks); a task shown as `<namespace>:<task>`
is that key in the included file. See
[the Taskfile standard](docs/standards/taskfile/index.md) for the conventions.

# Development Environment

All binaries, tools, and PATH are managed by **Nix**. Do not install tools manually or modify PATH outside of the nix configuration.

## Prerequisites

1. **[Nix](https://nixos.org/download)** — package manager
2. **[Docker](https://docs.docker.com/get-docker)** — container runtime
3. **[direnv](https://direnv.net/docs/installation.html)** — auto-loads the nix shell on `cd`

## Getting Started

```bash
direnv allow    # first time only — loads the nix dev shell
```

Once allowed, direnv automatically loads the development environment whenever you enter the project directory.

## Nix Configuration

See [docs/standards/nix/index.md](docs/standards/nix/index.md) for the full guide on:

- File structure (`flake.nix`, `nix/`, `.envrc`)
- Adding/removing packages
- Environment groups and shells
- Formatters and pre-commit hooks
- Adding registries

# Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

# Workspace baseline

This tree is the all-features workspace baseline inherited by every downstream sample: split CI/CD, secrets, release configuration, validators, and standards.
