---
id: semantic-release
title: Semantic Release
---

# Semantic Release

## What this covers

`release.yaml` is the single source of truth for the commit types, the
release level each one produces, the message rules the commit-msg hook applies, the
generated commit-convention document, and how a release commits and publishes.
Everything about releases in this repository is configured in that one file. There
is no standalone `.gitlint` file and one must not be added.

The tool that reads it is registry-supplied `releaser` v2, and it **replaces** semantic-release: there is
no plugin list, no package manager invoked at release time, and no separate
`.releaserc.yaml`. The configuration is `schemaVersion: 2`.

## What works today, and what does not

Everything on this page runs. `releaser` is in the `dev` and `releaser` package
groups, so it is on `PATH` in the default shell and in the release shell:

- commit messages are checked — the `a-releaser-commit` commit-msg hook calls
  `releaser lint-commit`; see [the linting standard](../linting/index.md);
- a release runs end to end from `⚡reusable-release.yaml`;
- the commit-conventions document `docs/developer/CommitConventions.md` is hand-written and kept in step with this file by a probe.

**Nothing runs a schema gate as a separate step**, and it does not need one: every
`releaser` subcommand loads and validates this file before it does anything, and
refuses with the offending field named. The standalone validator script that used to
assert the shape was deleted because it duplicated the tool. Break the file and
`releaser lint-commit` fails on your next commit — which is the earliest place a
check could fire.

## How releases are configured

The configuration is one document with five top-level parts.

- `types:` and `specialScopes:` are the commit vocabulary — each type carries a
  `desc`, an optional changelog `section`, and its scopes with the release level
  each one produces.
- `keywords:` are the breaking-change markers.
- `lint:` holds the message rules `releaser lint-commit` applies: header length,
  forbidden words, trailing punctuation, body line length, and the commit kinds it
  ignores outright (merges, reverts, fixups, squashes).
- `conventions:` is required by the releaser. Its `path` is the ignored scratch file
  `.releaser/conventions.md`; the document people read is the hand-written
  `docs/developer/CommitConventions.md`. See "The generated document" below.
- `release:` is the release itself: which `branches` may release, the `tagFormat`,
  the `changelog` path and title, the `commit` message and `assets`, whether a
  `github` release is published, and `hooks`.

Two parts of `release:` carry a note worth reading before you edit them:

- `release.hooks.prepare` is **deliberately empty**. It is where the old
  `@semantic-release/exec` hook point moved to: a list of
  `{ phase: beforeWrite | afterWrite, command: … }` entries a downstream node
  fills, usually with an `afterWrite` command that stamps the version into whatever
  file that node's ecosystem versions. This workspace versions no manifest, so it
  fills nothing. The releaser does not write a version file on its own — it writes
  only the changelog and the scratch conventions file — so there is no version file
  here to commit, and that is why there is none in `assets`.
- `release.commit.assets` lists the files a release commits, and it is enforced
  rather than advisory: the releaser aborts if a write lands outside the list, and a
  file listed but never written is dead configuration. So if you add a `prepare`
  command that writes a file, add that file to `assets` **in the same edit**.

Commit linting and release calculation read this same configuration, so there is
only one vocabulary to keep correct.

## The conventions document

`docs/developer/CommitConventions.md` is hand-written. Edit it directly and keep its
types table in step with `types:` in `release.yaml`; a probe fails when the two
differ. It carries no scopes.

The releaser still requires a `conventions` block. `conventions.path` points at
`.releaser/conventions.md`, which is gitignored scratch output that the releaser
regenerates (scope tables included) and nobody reads or commits. Do not point it at
the hand-written document, and do not run `releaser conventions` to update that
document.

`treefmt` formats the hand-written document like any other Markdown file (prettier aligns
its tables), and the probe reads the type table after that formatting.

## How a release is triggered

Release is its own workflow, and it runs off a successful `CI` run rather than off
a push. `.github/workflows/release.yaml` declares that `workflow_run` trigger, the
restriction to `main`, and the `release` concurrency group; the `a-workflows` gate
pins those values through `dlint.yaml`'s
`checks["workflow-policy"].assertions`. The trigger and concurrency probes each
sabotage their own value and drive that check directly, so both independent
release policies are shown able to fail.

The workflow ends in a single `scripts/ci/release.sh` call inside the `releaser`
Nix shell. That script runs `releaser release -c release.yaml`, which
calculates the version, writes the changelog, commits
the configured assets, tags, pushes, and publishes the GitHub release.

It clears `.git/hooks` first, and that line is load-bearing: the release commit's
message begins `release:`, which is not one of the configured commit types, so the
commit-msg hook would refuse the commit the tool is in the middle of making.

## Commands

```bash
releaser next                          # the version the current commits would produce
releaser changelog                     # the release notes they would produce
releaser conventions -c release.yaml   # writes the ignored scratch file; not the hand-written doc
releaser release --dry-run             # everything a release would do, changing nothing
releaser release -c release.yaml       # the real thing; CI runs this one
```

`releaser release` without `--dry-run` is the only command that changes git or
publishes anything. `next`, `changelog` and `release` all refuse unless the current
branch is listed in `release.branches`, so on a feature branch they report that
rather than guessing.

`releaser conventions` writes only the ignored `conventions.path` scratch file. The
commit-types document people read, `docs/developer/CommitConventions.md`, is edited
by hand.
