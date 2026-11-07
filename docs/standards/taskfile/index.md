---
id: taskfile
title: Taskfile Conventions
---

# Taskfile Conventions

`task` (go-task) is the repository task runner — the only one. Root tasks live in
`Taskfile.yaml`; grouped tasks live under `tasks/` and are included by namespace.

## Reading the task surface

`task --list` prints every available task with its description; that output is the
current surface. To read it from source instead, start at `Taskfile.yaml`: its
`includes:` block maps each namespace to a file under `tasks/`, so a task shown as
`<namespace>:<task>` is the `<task>` key in the file that namespace includes.
Every task carries a `desc:` explaining what it does, and its `cmds:` are the
literal commands it runs.

The root `setup` task owns generated workspace assets. It runs
`releaser conventions -c release.yaml` and then the only permitted vendor-tree
writer, `skills-sync sync`. Setup is repair-capable; the pre-commit hook
(`skills-sync sync --frozen`, which CI runs) refuses rather than silently staging or
repairing a commit.

## Rules

1. Keep simple commands inline: a task may run several, use a template expression
   such as `{{if .CLI_ARGS}}…{{end}}`, or end one command with `|| true`.
2. Move shell control flow (`if`/`elif`/`else`/`fi`, `case`, `for`/`while` loops,
   functions) to `scripts/local/`.
3. Never call `scripts/ci/*` from a Taskfile; workflows own those entry points.
4. Use lowercase names and colon-separated namespaces.
5. Do not add progress-only `echo` commands; the runner already displays each
   command.

Each include remains self-contained so downstream strips can remove only their own
axis.
