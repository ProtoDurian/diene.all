# shell-scripts

durian.cloud > engineering > standards > shell-scripts

How shell scripts are written and where they live

| Word | Means | Also called | See |
|---|---|---|---|
| CI script | A lane entry point in scripts/ci/; only GitHub workflows invoke it, and a Taskfile never calls one. |  | [local script](#local-script), [validate script](#validate-script) |
| local script | A developer-facing helper in scripts/local/; Taskfiles invoke these, and a developer may run one directly. |  | [CI script](#ci-script), [validate script](#validate-script) |
| progress echo | An emoji-prefixed echo that shows what a script is doing; encouraged, but never a no-op placeholder such as echo Completed. |  |  |
| required header | The first lines of every script, a bash shebang via env and set -euo pipefail. |  |  |
| validate script | A repository-owned policy check in scripts/validate/, invoked by pre-commit hooks. |  | [CI script](#ci-script), [local script](#local-script) |

## CI script

## local script

## progress echo

## required header

## validate script
