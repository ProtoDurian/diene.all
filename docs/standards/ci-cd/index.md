---
id: ci-cd
title: CI/CD Workflows
---

# CI/CD Workflows

GitHub Actions supplies triggers, permissions, runners, and inputs. Repository
logic stays in executable `scripts/ci/*.sh` files and runs through the matching
dev shell.

## Reading the workflow set

The workflows are `.github/workflows/`. Two kinds live there, distinguished by
their trigger block:

- **Orchestrators** — a `name:` plus real event triggers (`on.push`,
  `on.pull_request`, `on.workflow_run`). Their jobs do no work themselves: each
  job is a `uses:` pointing at a repository-local reusable workflow, with
  `permissions:`, `secrets: inherit`, and any repository-specific `with:` inputs.
  Read a job's `uses:` to see which lane it runs, and the orchestrator's `on:`
  block to see when.
- **Reusable workflows** — `on.workflow_call` only, named with a `⚡` prefix.
  Each owns runner selection and setup and ends in a `run:` line of the form
  `durian-shell .#<shell> -c ./scripts/ci/<script>.sh`.
  - `durian-shell` comes from `AtomiCloud/actions.setup-nix` (v4): it is `nix develop -c` with the evaluated dev shell kept
    on the cache volume, and plain `nix develop` anywhere it cannot cache. The v4 defaults apply, so setup-nix steps pass
    no tuning inputs.
  - Helm checks out through setup-nix with `fetch-depth: '1'` (shallow checkout).
  - The Named Checks job runs in the `default` dev shell (`durian-shell .#default`); the Helm job runs in `ci`, which has no `go-task`.
  - Locally the same line is `nix develop .#<shell> -c ./scripts/ci/<script>.sh`.
  - The Pre-Commit job enters the `precommit` dev shell and runs `pre-commit run --all-files`, so every pre-commit hook runs, including `a-skills-sync` (`skills-sync sync --frozen`), so CI enforces
    the vendored skills without a separate step, and `a-ul` (`scripts/validate/ul.sh`: `ul check`, a check that every word is in its standard's docs, then `ul gen --check`), so CI enforces the UL without a separate job.

  Callers grant permissions, pass only repository-specific values, and use
  `secrets: inherit`. The `a-workflows` quality gate enforces that every orchestrator job
  resolves to a repository-local reusable workflow, that each reusable workflow
  calls an existing, executable `scripts/ci` entry point, and that the release
  workflow keeps its trigger and concurrency group.

`AtomiCloud/actions.setup-nix` checks out the repository, so do not add an
adjacent `actions/checkout`.

## Action pins

Trusted actions use major pins; every other action uses an exact 40-character SHA
plus its tag in a trailing comment. Which actions are trusted is one regex,
`dlint.yaml`'s `checks["action-pins"].trustedPattern`: an action matching it is
trusted, everything else is non-trusted by default — so an action nobody thought
about gets the strictest pin.

## Every job declares its dependencies

> **Every `run:` step enters a dev shell that declares what it needs.**

The Docker job is the one exception: it runs `./scripts/ci/docker.sh` directly, with no dev shell and no Nix store cache label.

In practice a `run:` step outside that job is exactly one line:

```text
nix develop .#<shell> -c <command>
```

`<shell>` is one of the dev shells declared in
[`nix/shells.nix`](../../../nix/shells.nix) — today `default`, `precommit`, `ci`, `cd` and
`releaser`. Three things follow: a job's dependencies are visible without reading
the job, CI and your laptop run the same tools, and every job can reuse the shared
Nix store cache. `default` and `precommit` install the git hook; `ci`, `cd` and `releaser` do not.

## Runners and cache labels

Every job that runs a script uses the same runner labels, written as the same
literal in every reusable workflow.

```yaml
runs-on:
  - nscloud-ubuntu-26.04-amd64-<size>-with-cache
  - nscloud-cache-size-40gb
  - nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64
```

This is one template value with a default. The runner and the Nix store cache
tag are chosen once, when a repository is generated from the template, and the
answer is written into every workflow identically. Reusable workflows take no
runner or cache inputs and callers never pass them, so there is one value to
change, and every workflow changes with it.

Selection is 26.04-first; the 24.04 equivalents are the fallbacks. A lane that
must **not** share the store uses the bare `nscloud-ubuntu-26.04-amd64-<size>` with
no cache labels at all — a bare label cannot attach a cache volume, which is the
point of using it. The cache tag
is shared per OS and architecture: it carries no organization, platform or
service name, and changing the OS rotates the tag and costs one cold build before
warm reuse resumes. The merge gatekeeper is a poller with no Nix, so it stays on
GitHub-hosted `ubuntu-26.04`.

The release-note job (`⚡reusable-release-note.yaml`) is the other exception.
It only echoes the release version, so it runs on GitHub-hosted
`ubuntu-26.04` with `actions/checkout` and no Nix, and calls
`./scripts/ci/release-note.sh` directly.

## Dependency materialisation

Each lane's `run:` line enters a dev shell, and the dev shell is the whole of that
lane's dependency contract: there is no separate setup entry point to call first.

A language template built from this one materialises its own ecosystem's packages
— a .NET node its `dotnet restore`, a Node node its install — in its own
configuration, not through an extension point here. A new language therefore
changes one place.

## Local reproduction

Run the same entry point the lane runs. Take the `run:` line from the reusable
workflow you want to reproduce and run it verbatim, for example:

```bash
nix develop .#precommit -c ./scripts/ci/pre-commit.sh
```

That line reproduces the pre-commit workflow (the `precommit` dev shell, which installs the git hook). The workspace template names no runtime, so its
`a-skills-sync` pre-commit hook is deliberately inert here.

The Docker and Helm scripts build locally by default. Their reusable workflows set
the documented environment contract to enable publishing.

## Artifact publishing

Docker and Helm callers pass per-repository image or chart values through workflow
`with:` inputs. Empty release versions produce commit builds; CD passes the tag as
the version. Charts push under their own path, `ghcr.io/<repo>/charts/<chart name>`, so a chart never replaces an
image tag. Add another image or chart as another caller job rather than putting
repository-specific branching into the reusable workflow.

Release execution runs the real tool: `⚡reusable-release.yaml` enters the
`releaser` dev shell and calls `scripts/ci/release.sh`, which invokes
`releaser release -c release.yaml`. The `releaser` dev shell installs no git hook, so the commit-msg pre-commit hook
does not see the release commit, whose `release:` prefix is not a configured commit type.
