# taskfile

durian.cloud > engineering > standards > taskfile

How the one repository task runner is organised

| Word | Means | Also called | See |
|---|---|---|---|
| go-task | The repository task runner, the only one; task --list prints every task with its description. |  | [Taskfile includes](#taskfile-includes), [setup task](#setup-task) |
| setup task | The root task that owns the generated assets of the workspace template; it runs skills-sync sync, the only permitted vendor-tree writer. |  | [go-task](#go-task) |
| Taskfile includes | The includes block in Taskfile.yaml that maps each namespace to a file under tasks/; a task shown as namespace:task is the task key in that file. |  | [go-task](#go-task) |

## go-task

**Meaning**

The only task runner in the repository, run as the `task` command. `task --list` prints every available task with its description, and that output is the current surface. Every task carries a `desc:` and its `cmds:` are the literal commands it runs. It is in the `dev` environment group, so it is in the `default` dev shell and not in `ci`.

**Examples**

From `Taskfile.yaml`:

```yaml
lint:
  desc: Run all repository gates
  cmds:
    - pre-commit run --all-files
```

Run it with `task lint`.

## setup task

**Meaning**

The root task `setup`. It owns the generated assets of the workspace template and runs `skills-sync sync`, the only permitted writer of the vendor tree. It is repair-capable, unlike the pre-commit hook `skills-sync sync --frozen`, which refuses rather than silently staging or repairing a commit.

**Examples**

From `Taskfile.yaml`:

```yaml
setup:
  desc: Set up the workspace
  cmds:
    - ./scripts/local/setup.sh
```

`scripts/local/setup.sh` runs `releaser conventions -c release.yaml` and `skills-sync sync`.

## Taskfile includes

**Meaning**

The `includes:` block of `Taskfile.yaml`. It maps each namespace to a file under `tasks/`, so a task shown as `<namespace>:<task>` is the `<task>` key in the file that namespace includes. Docker and Helm tasks are keyed by the artifact they act on, one task set per Dockerfile and per chart.

**Examples**

From `Taskfile.yaml`:

```yaml
includes:
  docker: tasks/Taskfile.docker.yaml
  helm: tasks/Taskfile.helm.yaml
```

So `docker:build:main` is the `build:main` task in `tasks/Taskfile.docker.yaml`.
