---
name: diene-go-interfaces-usage
description: Use the Diene Go effect ports (System, Vfs, Terminal, LoggerSink, MetricsCollector) and their in-memory test doubles.
---

# Diene Go interfaces usage

The package docs are the reference: `go doc github.com/ProtoDurian/diene.go-interfaces/lib/interfaces`
and `go doc github.com/ProtoDurian/diene.go-interfaces/testhelper` (or pkg.go.dev). Every export has a
runnable `Example`.

## Ports

Import `github.com/ProtoDurian/diene.go-interfaces/lib/interfaces` and depend on the port, never on a
host type. Concrete adapters live in the consuming runtime, not here.

- `System` (environment, working directory, UTC clock, delay), `Vfs` (files and directories),
  `Terminal` (process runs), `LoggerSink` and `MetricsCollector` (telemetry emission).
- Every fallible method returns `(T, error)`; a non-nil error carries a `*problem.Error` from
  `github.com/AtomiCloud/diene.go-errors-problems/lib/problem`. Recover it with `errors.As`.
- `System.Environment` returns nil for an unset variable and a pointer to `""` for an empty one;
  `CurrentDirectory` is absolute; `Delay` returns early with an error when the context is done.
- A non-zero `TerminalOutput.ExitCode` is captured output, not an error; only a launch failure is.
- Build values with `NewTerminalCommand`, `NewLogRecord`, `NewMetricRecord` and `NewVfsEntry` so
  caller slices and maps are copied and times are UTC.

## Vfs rules

- Paths are opaque to the port; `InMemoryVfs` normalizes them (`//a//b` is `/a/b`).
- A write needs an existing parent directory unless `WriteOptions.CreateParents` is set.
- `List` returns direct children only unless `ListOptions.Recursive` is set; listing a file or a missing
  path fails.
- `CreateDirectory` needs an existing parent unless `DirectoryOptions.Recursive` is set; creating an
  existing directory is a no-op.
- `Delete` refuses a non-empty directory unless `DirectoryOptions.Recursive` is set.
- A path is a file or a directory, never both: writing onto a directory, creating a directory onto a file,
  or going through a file as a parent fails.

## Test doubles

Import `github.com/ProtoDurian/diene.go-interfaces/testhelper` in tests only.

- `NewInMemorySystem`, `NewInMemoryVfs`, `NewInMemoryTerminal`, `NewInMemoryLoggerSink` and
  `NewInMemoryMetricsCollector` return deterministic doubles; seed them through their options.
- Script the next results with the `Enqueue…Result` methods (FIFO). A scripted plain error comes back
  as a `*problem.Error` that still matches the original with `errors.Is`; a problem error is returned
  unchanged.
- An unscripted `InMemoryTerminal.Run` fails with a 500 problem, so script every run you expect.
- Inspect what happened with `RequestedDelays`, `Files`, `Directories`, `Commands` and `Records`;
  each returns a copy.
- `InMemorySystem.Delay` never sleeps; with no scripted result it fails with the context error once the
  context is done.

## Double faults

Each fault is a `*problem.Error` whose type URI is
`https://docs.diene.atomicloud.com/docs/diene/go/interfaces/testhelper/v1/<id>`, with `Detail` set to the
path or executable and `Data` set to `{"id": "<id>"}`. Assert on the id and status, not the message.

| id                             | status | when                                                                              |
| ------------------------------ | ------ | --------------------------------------------------------------------------------- |
| `path-not-found`               | 404    | the path, or the parent a write or create needs, is absent; also `List` on a file |
| `directory-not-empty`          | 409    | a non-recursive delete of a directory with entries                                |
| `path-is-directory`            | 409    | a write onto a directory                                                          |
| `path-is-file`                 | 409    | a directory create onto a file                                                    |
| `not-a-directory`              | 409    | a write or create whose ancestor is a file                                        |
| `terminal-result-not-scripted` | 500    | `InMemoryTerminal.Run` with no scripted result                                    |
