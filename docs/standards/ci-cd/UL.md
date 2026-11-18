# ci-cd

durian.cloud > engineering > standards > ci-cd

How GitHub Actions workflows call repository scripts through Nix dev shells

| Word | Means | Also called | See |
|---|---|---|---|
| a-workflows | The quality gate that checks orchestrator jobs call local reusable workflows, scripts/ci entry points exist and run, and release keeps its trigger. |  | [orchestrator](#orchestrator), [reusable workflow](#reusable-workflow) |
| action pin | How a workflow action is versioned; trusted actions use a major pin and every other action an exact 40-character SHA with its tag in a comment. |  | [trusted action](#trusted-action) |
| commit build | A build made from an empty release version; CD passes the tag as the version for a release. |  |  |
| durian-shell | The setup-nix command that is nix develop -c with the evaluated dev shell kept on the cache volume; locally the line is nix develop .#name -c script. |  | [reusable workflow](#reusable-workflow) |
| Nix store cache | The Nix store cache that jobs share; its tag carries the OS and architecture, and no organization, platform or service name. |  |  |
| orchestrator | A workflow with real event triggers whose jobs only call a repository-local reusable workflow with permissions, secrets and inputs. | caller job | [reusable workflow](#reusable-workflow) |
| reusable workflow | A workflow with on.workflow_call only, named with a ⚡ prefix; it owns the runner and setup and ends in a durian-shell run line. |  | [orchestrator](#orchestrator), [durian-shell](#durian-shell) |
| trusted action | An action matching the one regex trustedPattern in dlint.yaml; every other action is non-trusted by default. |  | [action pin](#action-pin) |

## a-workflows

**Meaning**

The quality gate that checks every orchestrator job resolves to a repository-local reusable workflow, that each reusable workflow calls an existing, executable `scripts/ci` entry point, and that the release workflow keeps its trigger and concurrency group.

**Examples**

Its configuration is the `ci-wiring` check in `dlint.yaml`:

```yaml
ci-wiring:
  workflowsDir: .github/workflows
  entrypointPattern: scripts/ci/[A-Za-z0-9._-]+[.]sh
```

It runs inside `dlint lint`, which the `a-dlint` hook in `nix/pre-commit.nix` runs.

## action pin

**Meaning**

How a workflow action is versioned. A trusted action uses a major pin; every other action uses an exact 40-character SHA plus its tag in a trailing comment. An action nobody thought about is non-trusted, so it gets the strictest pin.

**Examples**

Trusted, major pin, in `.github/workflows/⚡reusable-precommit.yaml`: `uses: AtomiCloud/actions.setup-nix@v4`.

Non-trusted, exact SHA, in `.github/workflows/🛡️merge-gatekeeper.yml`:

```yaml
uses: upsidr/merge-gatekeeper@09af7a82c1666d0e64d2bd8c01797a0bcfd3bb5d # v1.2.1
```

## commit build

**Meaning**

A build made from an empty release version. For a release, CD passes the tag as the version.

**Examples**

From `.github/workflows/cd.yaml`, the release path, where the tag is the version:

```yaml
version: ${{ github.ref_name }}
```

`.github/workflows/ci.yaml` passes no version to the Docker job, so it is a commit build.

## durian-shell

**Meaning**

The command from `AtomiCloud/actions.setup-nix` (v4). It is `nix develop -c` with the evaluated dev shell kept on the cache volume, and plain `nix develop` anywhere it cannot cache. Locally the same line is `nix develop .#<shell> -c ./scripts/ci/<script>.sh`.

**Examples**

From `.github/workflows/⚡reusable-precommit.yaml`: `durian-shell .#precommit -c ./scripts/ci/pre-commit.sh`. Locally: `nix develop .#precommit -c ./scripts/ci/pre-commit.sh`.

## Nix store cache

**Meaning**

The Nix store cache that the jobs running a script share. Its tag is shared per OS and architecture and carries no organization, platform or service name. Changing the OS rotates the tag and costs one cold build before warm reuse resumes. The Docker job uses no Nix store cache label.

**Examples**

From `.github/workflows/⚡reusable-precommit.yaml`:

```yaml
runs-on:
  - nscloud-ubuntu-26.04-amd64-4x8-with-cache
  - nscloud-cache-size-40gb
  - nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64
```

## orchestrator

**Meaning**

A workflow with real event triggers (`on:`). Its jobs only call a repository-local reusable workflow, granting `permissions:`, passing `secrets: inherit` and any repository-specific `with:` inputs. The `a-workflows` quality gate enforces that every orchestrator job resolves to a local reusable workflow.

**Examples**

`.github/workflows/ci.yaml`, `.github/workflows/cd.yaml` and `.github/workflows/release.yaml`. From `ci.yaml`:

```yaml
precommit:
  name: Pre-Commit
  permissions:
    contents: read
  uses: ./.github/workflows/⚡reusable-precommit.yaml
  secrets: inherit
```

## reusable workflow

**Meaning**

A workflow with `on.workflow_call` only, named with a `⚡` prefix. It owns runner selection and setup and ends in a `run:` line of the form `durian-shell .#<shell> -c ./scripts/ci/<script>.sh`. Callers pass no runner or cache inputs.

**Examples**

`.github/workflows/⚡reusable-precommit.yaml`:

```yaml
on:
  workflow_call:
...
run: durian-shell .#precommit -c ./scripts/ci/pre-commit.sh
```

## trusted action

**Meaning**

An action matching the one regex `trustedPattern` under `checks["action-pins"]` in `dlint.yaml`. Every other action is non-trusted by default.

**Examples**

From `dlint.yaml`:

```yaml
trustedPattern: ^(AtomiCloud|ProtoDurian|actions)/
```

`actions/checkout@v7` in `.github/workflows/⚡reusable-release-note.yaml` is trusted.
