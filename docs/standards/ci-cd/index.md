---
id: ci-cd
title: CI/CD Workflows
---

# CI/CD Workflows

GitHub Actions supplies triggers, permissions, runners, and inputs. Repository
logic stays in executable `scripts/ci/*.sh` files and runs through the matching
Nix shell.

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
  `atomi-develop .#<shell> -c ./scripts/ci/<script>.sh`. `atomi-develop` comes from
  `AtomiCloud/actions.setup-nix` (`devshell-cache: 'true'`): it is `nix develop -c` with the
  evaluated shell kept on the cache volume, and plain `nix develop` anywhere it cannot
  cache. Locally the same line is `nix develop .#<shell> -c ./scripts/ci/<script>.sh`.
  Jobs that read no `GITHUB_*_SLUG` variable set `github-slug: 'false'`. The pre-commit script runs
  every hook, including `a-skills-sync` (`skills-sync sync --frozen`), so CI
  enforces the vendored skills without a separate step.

Callers grant permissions, pass only repository-specific values, and use
`secrets: inherit`. The `a-workflows` gate enforces that every orchestrator job
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

A trusted action must also be on its latest major. `.github/action-majors.yaml` records that major for every trusted
action the workflows use, and the `a-action-majors` hook (`scripts/local/action-majors.sh`, run in CI through pre-commit)
is red when a trusted action is below its recorded major, used but unlisted, or the list is empty or unreadable. Raising
a major is an edit to that file and to the workflows in the same change.

## Every job declares its dependencies

> **Every `run:` step enters a Nix shell that declares what it needs.**

The Docker job is the one exception: it runs `./scripts/ci/docker.sh` directly, with no Nix shell and no Nix store cache label.

In practice a `run:` step is exactly one line:

```text
nix develop .#<shell> -c <command>
```

`<shell>` is one of the shells declared in
[`nix/shells.nix`](../../../nix/shells.nix) — today `default`, `ci`, `cd` and
`releaser`. Three things follow: a job's dependencies are visible without reading
the job, CI and your laptop run the same tools, and every job can reuse the shared
Nix store cache.

## Runners and cache labels

Every job that runs a script uses the same runner labels, written as the same
literal in every reusable workflow. The machine size is the one part that differs:
Pre-Commit runs on `4x8`; every other Namespace job runs on `2x4`, which bills half
the units for the same speed on these jobs.

```yaml
runs-on:
  - nscloud-ubuntu-26.04-amd64-2x4-with-cache
  - nscloud-cache-size-20gb
  - nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64
```

This is one template value with a default. The runner and the Nix store cache
tag are chosen once, when a repository is generated from the template, and the
answer is written into every workflow identically. Reusable workflows take no
runner or cache inputs and callers never pass them, so there is one value to
change, and every workflow changes with it.

Selection is 26.04-first; the 24.04 equivalents are the fallbacks. A lane that
must **not** share the store uses the bare `nscloud-ubuntu-26.04-amd64-4x8` with
no cache labels at all — a bare label cannot attach a cache volume, which is the
point of using it. The cache tag
is shared per OS and architecture: it carries no organization, platform or
service name, and changing the OS rotates the tag and costs one cold build before
warm reuse resumes. The merge gatekeeper is a poller with no Nix, so it stays on
GitHub-hosted `ubuntu-26.04`.

The release-note job (`⚡reusable-release-note.yaml`) is the other exception.
It only echoes the release version, so it runs on GitHub-hosted
`ubuntu-latest` with `actions/checkout` and no Nix, and calls
`./scripts/ci/release-note.sh` directly.

## Dependency materialisation

Each lane's `run:` line enters a Nix shell, and the shell is the whole of that
lane's dependency contract: there is no separate setup entry point to call first.

A language template built from this one materialises its own ecosystem's packages
— a .NET node its `dotnet restore`, a Node node its install — in its own
configuration, not through an extension point here. A new language therefore
changes one place.

## Local reproduction

Run the same entry point the lane runs. Take the `run:` line from the reusable
workflow you want to reproduce and run it verbatim, for example:

```bash
nix develop .#ci -c ./scripts/ci/pre-commit.sh
```

That line reproduces the pre-commit workflow. Workspace names no runtime, so its
`a-skills-sync` hook is deliberately inert here.

The Docker and Helm scripts build locally by default. Their reusable workflows set
the documented environment contract to enable publishing.

## Artifact publishing

Docker and Helm callers pass per-repository image or chart values through workflow
`with:` inputs. Empty release versions produce commit builds; CD passes the tag as
the version. Add another image or chart as another caller job rather than putting
repository-specific branching into the reusable workflow.

Release execution runs the real tool: `⚡reusable-release.yaml` enters the
`releaser` shell and calls `scripts/ci/release.sh`, which invokes
`releaser release -c release.yaml`. That script clears `.git/hooks` first,
which is not incidental — the release commit's own message uses a `release:` prefix
that is not a configured commit type, so the commit-msg hook would refuse the
release the tool is in the middle of making.
