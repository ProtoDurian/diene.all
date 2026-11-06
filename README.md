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

`@atomicloud/diene.otel` wires OpenTelemetry for the AtomiCloud Bun family. It
ships the one OTel config block schema (per-signal `logs`, `metrics`, `traces`),
the resource identity mapping (landscape, platform, service, module and version
onto semantic-convention and `atomi.*` attributes), the init / flush / shutdown
lifecycle, OTLP http/protobuf export on port 4318 for metrics and traces, and pino
JSON logs with trace ids. Exporters are off by default. Shipped as dual
**ESM + CommonJS** with bundled types and two entry points: the package root and
`/test-helper`.

See the [otel standard](docs/standards/otel/index.md) for the contract and the
[npm release runbook](docs/developer/npm-release.md) for publishing.

[![npm version](https://img.shields.io/npm/v/@atomicloud/diene.otel)](https://www.npmjs.com/package/@atomicloud/diene.otel)
[![CI](https://github.com/AtomiCloud/diene.bun-otel/actions/workflows/ci.yaml/badge.svg)](https://github.com/AtomiCloud/diene.bun-otel/actions/workflows/ci.yaml)

### Installation

```bash
bun add @atomicloud/diene.otel
```

### Usage

```ts
import { OtelBootstrap, otelBlockSchema } from '@atomicloud/diene.otel';

const runtime = new OtelBootstrap().init(otelBlockSchema.parse(config.otel), config.app);
runtime.tracer.startActiveSpan('work', span => span.end());
await runtime.shutdown(); // call from your SIGTERM handler; the library registers none
```

In tests, inject the shared mocks from `@atomicloud/diene.interfaces/test-helper`
with `OtelTestHarness` from `@atomicloud/diene.otel/test-helper`.

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
