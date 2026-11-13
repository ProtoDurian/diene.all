# Commit conventions

This repository follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
Write `type: subject`, with no scope.

## Types

| Type | Use for |
| --- | --- |
| `amend` | Small amendments and typo fixes |
| `build` | Build-system changes |
| `chore` | Repository chores |
| `ci` | CI/CD changes |
| `config` | Configuration changes |
| `dep` | Dependency updates |
| `docs` | Documentation changes |
| `feat` | New features |
| `fix` | Bug fixes |
| `perf` | Performance improvements |
| `refactor` | Refactors |
| `style` | Non-functional style changes |
| `test` | Test changes |

- `release.yaml` is the machine-readable source of truth for the types.
- [The conventional-commits standard](../standards/conventional-commits/index.md)
  explains how to mark a breaking change.
- This file is generated: `releaser conventions` writes it from the
  `conventions.template` value in `release.yaml`, and a release run rewrites
  it. Change the template there rather than editing this file.

<!-- Generated scope reference, hidden on purpose: Use `type(scope)!: subject`. Omit `(scope)` only when the type's `default` scope applies.



## Types

| Type | Description | Release |
| --- | --- | --- |
| `amend` | Small amendments and typo fixes | no release |
| `build` | Build-system changes | no release |
| `chore` | Repository chores | no release |
| `ci` | CI/CD changes | no release |
| `config` | Configuration changes | no release |
| `dep` | Dependency updates | scope-dependent |
| `docs` | Documentation changes | no release |
| `feat` | New features | scope-dependent |
| `fix` | Bug fixes | patch |
| `perf` | Performance improvements | patch |
| `refactor` | Refactors | minor |
| `style` | Non-functional style changes | patch |
| `test` | Test changes | minor |

## Scopes



### `amend` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Amend existing work | no release |

### `build` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update build machinery | no release |

### `chore` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Perform a chore | no release |

### `ci` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update CI/CD | no release |

### `config` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update configuration | no release |

### `dep` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update a dependency | no release |
| `patch` | Patch dependency update | patch |
| `minor` | Minor dependency update | minor |
| `major` | Major dependency update | major |

### `docs` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update documentation | no release |

### `feat` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Add a feature | minor |
| `breaking` | Add a breaking feature | major |

### `fix` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Fix a bug | patch |

### `perf` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Improve performance | patch |

### `refactor` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Refactor implementation | minor |

### `style` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Update style | patch |

### `test` scopes

| Scope | Description | Release |
| --- | --- | --- |
| `default` | Add or correct tests | minor |

## Special scopes

| Scope | Description | Release |
| --- | --- | --- |
| `no-release` | Prevent release from happening | no release |

## V.A.E. guidance

No V.A.E. guidance is configured. -->
