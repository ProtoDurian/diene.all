# Agent skills

`.claude/skills/vendor/` is tool-owned and is never hand-edited. Nothing in this
tree writes it: the tool that does is consumed per-template from the Nix registry,
and this tree declares no packages for it to vendor.

# CI/CD workflows

See [docs/standards/ci-cd/index.md](docs/standards/ci-cd/index.md).

# Conventional commits

See [docs/standards/conventional-commits/index.md](docs/standards/conventional-commits/index.md).

# Development Environment

All binaries, tools, and PATH are managed by **Nix**. Do not install tools manually or modify PATH outside of the nix configuration.

## Prerequisites

1. **Nix** — package manager ([install](https://nixos.org/download))
2. **Docker** — container runtime ([install](https://docs.docker.com/get-docker))
3. **direnv** — auto-loads the nix shell on `cd` ([install](https://direnv.net/docs/installation.html))

## Getting Started

```bash
direnv allow    # first time only — loads the nix dev shell
```

## Nix Configuration

See **[docs/standards/nix/index.md](docs/standards/nix/index.md)** for the full guide on:

- File structure (`flake.nix`, `nix/`, `.envrc`)
- Adding/removing packages
- Environment groups and shells
- Formatters and pre-commit hooks
- Adding registries

# Docker build and publishing

See [docs/standards/docker/index.md](docs/standards/docker/index.md).

# Helm charts and publishing

See [docs/standards/helm/index.md](docs/standards/helm/index.md).

# Infisical and secrets

See [docs/standards/infisical/index.md](docs/standards/infisical/index.md).

# Linting and pre-commit

See [docs/standards/linting/index.md](docs/standards/linting/index.md).

# Release automation

See [docs/standards/semantic-release/index.md](docs/standards/semantic-release/index.md).

# Repository standards

Follow the linked standard before changing its surface.

# Service-tree identity

See [docs/standards/service-tree/index.md](docs/standards/service-tree/index.md).

# Shell scripts

See [docs/standards/shell-scripts/index.md](docs/standards/shell-scripts/index.md).

# Taskfile conventions

See [docs/standards/taskfile/index.md](docs/standards/taskfile/index.md).
