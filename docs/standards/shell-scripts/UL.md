# shell-scripts

durian.cloud > engineering > standards > shell-scripts

How shell scripts are written and where they live

| Word | Means | Also called | See |
|---|---|---|---|
| developer-facing helper | A script in scripts/local/; Taskfiles invoke these, and a developer may also run one directly. |  | [lane entry point](#lane-entry-point), [policy check](#policy-check) |
| lane entry point | A CI/CD script in scripts/ci/; only GitHub workflows invoke these, and a Taskfile must never call one. |  | [developer-facing helper](#developer-facing-helper), [policy check](#policy-check) |
| policy check | A repository-owned script in scripts/validate/, invoked by pre-commit hooks. |  | [lane entry point](#lane-entry-point), [developer-facing helper](#developer-facing-helper) |
| progress echo | An emoji-prefixed echo that shows what a script is doing; encouraged, but a no-op placeholder such as echo Completed is not. |  |  |
| required header | The first lines of every script, a bash shebang via env and set -euo pipefail. |  |  |

## developer-facing helper

## lane entry point

## policy check

## progress echo

## required header
