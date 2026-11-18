# ci-cd

durian.cloud > engineering > standards > ci-cd

How GitHub Actions workflows call repository scripts through Nix shells

| Word | Means | Also called | See |
|---|---|---|---|
| a-workflows | The gate that checks every orchestrator job calls a local reusable workflow, scripts/ci entry points exist and are executable, and release keeps its trigger. |  | [orchestrator](#orchestrator), [reusable workflow](#reusable-workflow) |
| action pin | How a workflow action is versioned; trusted actions use a major pin and every other action an exact 40-character SHA with its tag in a comment. |  | [trusted action](#trusted-action) |
| commit build | A build made from an empty release version; CD passes the tag as the version for a release. |  |  |
| durian-shell | The setup-nix command that is nix develop -c with the evaluated shell kept on the cache volume; locally the line is nix develop .#shell -c script. |  | [reusable workflow](#reusable-workflow) |
| Nix store cache | The Nix store cache that jobs share; its tag carries the OS and architecture, and no organization, platform or service name. |  |  |
| orchestrator | A workflow with real event triggers whose jobs only call a repository-local reusable workflow with permissions, secrets and inputs. | caller job | [reusable workflow](#reusable-workflow) |
| reusable workflow | A workflow with on.workflow_call only, named with a ⚡ prefix; it owns the runner and setup and ends in a durian-shell run line. |  | [orchestrator](#orchestrator), [durian-shell](#durian-shell) |
| trusted action | An action matching the one regex trustedPattern in dlint.yaml; every other action is non-trusted by default. |  | [action pin](#action-pin) |

## a-workflows

## action pin

## commit build

## durian-shell

## Nix store cache

## orchestrator

## reusable workflow

## trusted action
