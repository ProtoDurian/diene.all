# docker

durian.cloud > engineering > standards > docker

How Dockerfiles are built and published, one task set and one caller job per image

| Word | Means | Also called | See |
|---|---|---|---|
| local tag suffix | Optional text passed after -- to a Docker task; it is appended to the local tag, and run and clean take the same local tag suffix. |  |  |

## local tag suffix

**Meaning**

Text you pass after `--` to a Docker task. It is appended to the `:local` tag with a dash, so you can keep several local images of the same Dockerfile side by side. The `run` and `clean` tasks take the same local tag suffix, so they act on the image you built.

**Examples**

From `docs/standards/docker/index.md`:

```bash
task docker:build:main            # -> diene-workspace:local
task docker:build:main -- 1       # -> diene-workspace:local-1
task docker:build:main -- hello   # -> diene-workspace:local-hello
```

In `tasks/Taskfile.docker.yaml` the local tag suffix is `CLI_ARGS`, appended to the image name:

```yaml
- docker build -f infra/Dockerfile -t {{.IMAGE}}{{if .CLI_ARGS}}-{{.CLI_ARGS}}{{end}} .
```
