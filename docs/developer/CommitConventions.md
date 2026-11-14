# Commit conventions

This repository follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
Write `type: subject`, with no scope.

## Types

| Type       | Use for                         |
| ---------- | ------------------------------- |
| `amend`    | Small amendments and typo fixes |
| `build`    | Build-system changes            |
| `chore`    | Repository chores               |
| `ci`       | CI/CD changes                   |
| `config`   | Configuration changes           |
| `dep`      | Dependency updates              |
| `docs`     | Documentation changes           |
| `feat`     | New features                    |
| `fix`      | Bug fixes                       |
| `perf`     | Performance improvements        |
| `refactor` | Refactors                       |
| `style`    | Non-functional style changes    |
| `test`     | Test changes                    |

- `release.yaml` is the machine-readable source of truth for the types.
- [The conventional-commits standard](../standards/conventional-commits/index.md)
  explains how to mark a breaking change.
- Keep this table in step with the types in `release.yaml`; a probe fails when
  they differ.
