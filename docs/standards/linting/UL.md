# linting

durian.cloud > engineering > standards > linting

How lints run the same way locally, in commits and in CI

| Word | Means | Also called | See |
|---|---|---|---|
| dlint | The tool that runs every check configured in dlint.yaml as one pre-commit hook. |  | [pre-commit hook](#pre-commit-hook) |
| pre-commit hook | A check declared in nix/pre-commit.nix and run by pre-commit; custom ones are named with an a- prefix. |  | [dlint](#dlint) |

## dlint

**Meaning**

The tool behind the `a-dlint` pre-commit hook. The checks are configured in `dlint.yaml`; to add or disable a check, edit that file, not `nix/pre-commit.nix`.

**Examples**

The command the pre-commit hook runs: `dlint lint`.

From `dlint.yaml`:

```yaml
checks:
  action-pins:
    trustedPattern: ^(AtomiCloud|ProtoDurian|actions)/
    workflowsDir: .github/workflows
```

## pre-commit hook

**Meaning**

One entry in the `hooks` set of `nix/pre-commit.nix`: the tool and the files pattern it runs on. The hook set is the single source of truth, so local commits, `task lint` and CI all run the same pre-commit hooks. CI runs them with `pre-commit run --all-files`. Custom hooks are named with an `a-` prefix. To add a lint, add a pre-commit hook; only when it is too slow for every commit may a CI-only concern be wired into the workflows instead.

**Examples**

The pre-commit hook `a-ul` in `nix/pre-commit.nix`:

```nix
a-ul = {
  enable = true;
  name = "UL checks";
  entry = "${packages.atomiutils}/bin/bash -c 'PATH=${envPath}:\$PATH ./scripts/validate/ul.sh'";
  files = "^docs/.*\\.(md|yaml)$|(^|/)UL\\.(yaml|md)$";
  always_run = true;
  language = "system";
  pass_filenames = false;
};
```

Run them with `pre-commit run` (staged files) or `task lint` (everything, as CI does).
