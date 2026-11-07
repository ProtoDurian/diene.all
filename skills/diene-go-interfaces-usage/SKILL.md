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
- `System.Environment` returns nil for an unset variable and a pointer to `""` for an empty one.
- A non-zero `TerminalOutput.ExitCode` is captured output, not an error; only a launch failure is.
- Build values with `NewTerminalCommand`, `NewLogRecord`, `NewMetricRecord` and `NewVfsEntry` so
  caller slices and maps are copied and times are UTC.

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
- `InMemorySystem.Delay` never sleeps and ignores the context.
