# Commands

Run `task --list` for every available task and its description. The task set is
declared in [`Taskfile.yaml`](Taskfile.yaml).
Its `includes:` block maps each namespace to a file under [`tasks/`](tasks); a task
shown as `<namespace>:<task>` is that key in the included file.
Build artifacts live under [`infra/`](infra) and may be plural, so their tasks are
keyed per artifact.
Each Helm chart is a build artifact.
See [the Taskfile standard](docs/standards/taskfile/index.md) for the conventions.

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

This tree is the all-features workspace baseline inherited by every downstream sample:

- split CI/CD
- Helm
- secrets
- release configuration
- validators
- standards

# Helm wrapper

This branch adds the wrapper chart, stacked values, generated schema, rendered-manifest validation, and dual publish modes.

- `task build` — vendor external config and build pinned chart dependencies.
- `pre-commit run --all-files` — run the three chart-check hooks: helm lint, the values-schema generator, and `chart-checks` on the rendered manifests.
- `task example:lapras:template` — render the independent landscape + cluster stack.
- [Helm wrapper baseline](docs/developer/helm-wrapper-baseline.md)
