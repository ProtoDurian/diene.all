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

`@atomicloud/diene.problems` is the Bun family's RFC 9457 Problem Details
machinery: the `Problem` envelope with its typed `data` extension, a Zod-typed
registry, the error and HTTP transformer, the single versioned type URI
builder, the six generic problems, and the emitters that publish a service's
catalog as a manifest and as per-row `Problem` resources. Every member is a
stateless class; `tryRegister` returns a `Result` from
`@atomicloud/diene.result`. The `@atomicloud/diene.problems/test-helper`
subpath ships the `expectProblem` matcher and registry-aware builders. It ships
dual **ESM + CommonJS** with bundled type declarations. See the
[problems standard](docs/standards/problems/index.md) and the shipped
[usage skill](skills/diene-problems-usage/SKILL.md).

See the [npm release runbook](docs/developer/npm-release.md) for tag publishing.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.problems)](https://www.npmjs.com/package/@atomicloud/diene.problems)
[![npm downloads](https://img.shields.io/npm/dm/@atomicloud/diene.problems)](https://www.npmjs.com/package/@atomicloud/diene.problems)
[![CI](https://github.com/AtomiCloud/diene.bun-problems/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-problems/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.problems
# or
npm install @atomicloud/diene.problems
```

### Usage

```ts
import { GenericProblemCatalog, ProblemFactory } from '@atomicloud/diene.problems';
import { ProblemTestHelper } from '@atomicloud/diene.problems/test-helper';

const registry = new GenericProblemCatalog().createGenericProblemRegistry(portal);
const problem = new ProblemFactory().createProblem(registry.require('entity_not_found'), {
  data: { entityType: 'Note', id: '42' },
});
new ProblemTestHelper().expectProblem(problem).toBe(registry.require('entity_not_found'));
```

```js
const { GenericProblemCatalog } = require('@atomicloud/diene.problems');
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
