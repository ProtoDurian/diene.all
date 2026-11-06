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

`@atomicloud/diene.core-utils` is the Bun family's deterministic utility layer:
slugs and namespaced keys, timing, fuzzy matching, bounded concurrency, stable
records, SHA-256, dedupe, explicit-root path joins and the C0 Temporal wire-date
codecs. Every member is a stateless class; fallible domain results return a
`Result` from `@atomicloud/diene.result`, while programmer errors (a bad
`concurrency` or `seconds`, a cyclic config) throw or reject with a
`RangeError` or `TypeError`. It ships dual **ESM + CommonJS** with
bundled type declarations. See the
[core-utils standard](docs/standards/core-utils/index.md) and the shipped
[usage skill](skills/diene-core-utils-usage/SKILL.md).

See the [npm release runbook](docs/developer/npm-release.md) for tag publishing.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.core-utils)](https://www.npmjs.com/package/@atomicloud/diene.core-utils)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.core-utils)](https://www.npmjs.com/package/@atomicloud/diene.core-utils)
[![CI](https://github.com/AtomiCloud/diene.bun-core-utils/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-core-utils/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.core-utils
# or
npm install @atomicloud/diene.core-utils
```

### Usage

```ts
import { Slugger, WireDateCodec } from '@atomicloud/diene.core-utils';

const key = await new Slugger().namespacedKey('Billing', 'Invoice Total').unwrapOr('fallback');
const date = await new WireDateCodec().parseDate('2026-07-24').unwrap();
```

```js
const { Slugger } = require('@atomicloud/diene.core-utils');
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
