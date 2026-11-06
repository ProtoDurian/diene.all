# Observability Add-Back Checklist

This checklist is for the maintainers of the observability template. In a service repo, skip it. Use it when adding the observability payload to the template branches that ship with observability.

- **Template branch**: a branch of the template repository that generates one kind of service repo, e.g. `bun-base-w-observability`.
- **Parent branch / child branch**: a template branch is built by merging its parent branch into it; its child branches are built from it the same way.
- **Payload**: the files the `observability` branch adds on top of its base (the commit it was branched from), as `git diff <base> observability` shows.

## Before you start

- The `observability` branch is committed, clean and passes its checks.
- Each target branch's own parent branch is committed and green.
- Nobody has written service code on the target branch.

## Target branches

- `bun-base-w-observability`
- `bun-base-wo-helm-docker-w-observability`
- `dotnet-base-w-observability`
- `go-base-w-observability`

## For each target branch

1. If its parent branch has moved, merge the parent first.
2. Merge the `observability` branch with a merge commit. Never rebase, squash, cherry-pick or rewrite the payload files.
3. Check that the merge adds exactly the payload: `git diff <parent> <merge>` shows the same changes as `git diff <base> observability`.
4. Check that `probes/observability-*` (probes are tests under `probes/`, run with `bun test probes`, that check a feature's files exist) and the `observability-standards-present` row in `probes/features.json` arrived through the merge, not by hand.
5. Run all the branch's probes and CI checks; all must pass.
6. Write down the parent commit, the observability commit, the merge commit and the check results.

## After all four are green

- Merge each target branch into its own child branches only, and re-run each child's checks.
- Leave the language-specific OpenTelemetry and Faro tests with the branches that own that code.
- Stop before any check that needs a live environment until that environment is ready.
