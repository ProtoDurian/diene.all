# Linting

## Running lints

```bash
task lint            # everything, exactly what CI runs
pre-commit run       # the staged files only (what a commit runs)
```

CI runs `pre-commit run --all-files`, so the pre-commit hook set in `nix/pre-commit.nix` is
the single source of truth: local commits, `task lint`, and CI all execute the
same quality gates.

## Adding a lint

1. Add a pre-commit hook to `nix/pre-commit.nix` (one entry: the tool, its files pattern).
2. If the tool comes from the registry or nixpkgs, add it to `nix/packages.nix`.
3. Run `task lint` to see it fire.

That is the whole procedure. A lint that is too slow for every commit still goes
in pre-commit but CI-only concerns can be wired into the CI workflows instead —
prefer the pre-commit hook unless the cost is real.

Checks configured through `dlint.yaml` run as one pre-commit hook (`dlint lint`); add or
disable checks there.

The `a-ul` pre-commit hook runs `scripts/validate/ul.sh`: `ul check`, a check that every
word of a `UL.yaml` is in its engineering standard's docs, then `ul gen --check`. It runs
on every commit, including one that only deletes a doc (`always_run`, because pre-commit
hands a hook no deleted paths); its `files` pattern covers `.md` and `.yaml` under `docs/`
and any `UL.yaml` or `UL.md`. CI runs it through the Pre-Commit job; there is no separate UL job.
