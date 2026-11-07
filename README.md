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

# Go base template

See the [Go baseline](docs/developer/go-baseline.md) for the language-specific
toolchain, task surface, test tiers, coverage ledgers and dead-code passes.
Go variants accompany the shared standards for
[date/time](docs/standards/datetime/languages/go.md),
[domain-driven design](docs/standards/domain-driven-design/languages/go.md),
[functional practices](docs/standards/functional-practices/languages/go.md),
[SOLID](docs/standards/solid-principles/languages/go.md),
[stateless OOP/DI](docs/standards/stateless-oop-di/languages/go.md),
[testing](docs/standards/testing/languages/go.md),
[utilities](docs/standards/utilities/languages/go.md), and
[validation](docs/standards/validation/languages/go.md).

# Go library template

[![Go Reference](https://pkg.go.dev/badge/github.com/ProtoDurian/diene.go-errors-problems.svg)](https://pkg.go.dev/github.com/ProtoDurian/diene.go-errors-problems)
[![CI](https://github.com/ProtoDurian/diene.go-errors-problems/actions/workflows/ci.yaml/badge.svg)](https://github.com/ProtoDurian/diene.go-errors-problems/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

This module is `github.com/ProtoDurian/diene.go-errors-problems`. See the
[Go library baseline](docs/developer/go-lib-baseline.md) for the library shape,
the TestHelper tier, the library gates (`task validate`) and tag-based
publication through the Go proxy.

## Errors-problems library

- `lib/problem`: RFC 9457 problem errors for `(T, error)` results, the one
  type-URI builder, the generic catalog and the `Problem` resource export.
- `testhelper`: Problem assertions for id, status and `data`.
- No adapters, so the int tier is empty.
- Usage skill: [`skills/diene-go-errors-problems-usage`](skills/diene-go-errors-problems-usage/SKILL.md).

# Standards

The conventions this repository follows live under
[`docs/standards/`](docs/standards). Read the standard for the surface you are
changing before you change it. [`CLAUDE.md`](CLAUDE.md) links the ones an agent
reaches for most often; it is a convenience, not a required index, and nothing
checks that it names every surface.

# Workspace baseline

This tree is the all-features workspace baseline inherited by every downstream sample: split CI/CD, Docker, Helm, secrets, release configuration, validators, and standards.
