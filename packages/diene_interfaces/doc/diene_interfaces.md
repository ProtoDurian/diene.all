# diene_interfaces

`diene_interfaces` owns the ports between portable Dart code and the host, and
their test fakes. It owns no adapter.

## Ports

| Port               | Boundary                             | Members                                                                                                   |
| ------------------ | ------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `System`           | the running process's own state      | `environment`, `currentDirectory`, `nowUtc`, `delay`                                                      |
| `Vfs`              | the filesystem                       | `exists`, `stat`, `readBytes`, `readText`, `writeBytes`, `writeText`, `list`, `createDirectory`, `delete` |
| `Terminal`         | child processes and line-based stdio | `interactive`, `run`, `write`, `readLine`                                                                 |
| `LoggerSink`       | structured log emission              | `emit`, `flush`                                                                                           |
| `MetricsCollector` | metric sample emission               | `emit`, `flush`                                                                                           |

`System` answers about the running process; `Terminal` launches other ones. A
consumer that needs only a fake clock never has to take a process runner.

## Failures are `Result` values

Every fallible member returns `Result<T>` or `Future<Result<T>>` from
`diene_result` and never throws for an expected failure. The error is a
`Problem` from `diene_problems`.

- `portProblem` is the one place a port failure becomes a `Problem`. Its `type`
  comes from `problemTypeUri`, version `v1`, id `<port>_<code>` (for example
  `vfs_not_found`), on `ErrorPortal.localError` unless you pass your portal.
- Each `PortErrorCode` fixes the HTTP status and `recoverable`; only `timeout`
  and `unavailable` are recoverable.
- `data` always holds `port`, `code` and `operation`, plus any `details`.
  `instance` is never set, so it is left out of the wire form.
- An absent value is a success: an unset variable is `Ok(null)`, a missing path
  is `exists` → `Ok(false)`.
- A non-zero exit code is an `Ok(TerminalOutput)`; only a launch fault is `Err`.
- `portFailure` wraps a `portProblem` in `Err`; `invalidInput` is the
  `invalid_input` shortcut with a `field` detail.

The `check*` functions (`checkVfsPath`, `checkTerminalCommand`,
`checkTerminalOutput`, `checkTerminalWrite`, `checkTerminalRead`,
`checkLogRecord`, `checkMetricRecord`, `checkTelemetryAttributes`) are
validators an adapter may reuse. The port contracts do not require them: a
memory- or archive-backed `Vfs` may accept paths a POSIX host would not.

## What lives elsewhere

- **Pure helpers** (path, string and value utilities) live in
  `diene_core_utils`, not here. This package imports no `dart:io` and no
  `dart:isolate`, so it stays web-safe.
- **Real adapters** (process, filesystem, terminal, telemetry) belong to Flutter
  or to the runtime that hosts the app, because only that layer can choose
  directories, sandboxing and permissions.
- **No Dart OpenTelemetry.** Dart has no OpenTelemetry package. Runtime
  telemetry is frontend-only and travels through Faro in `flutter-base`; this
  package defines the logging and metrics ports and owns no exporter or vendor.

## TestHelper

`package:diene_interfaces/test_helper.dart` holds the fakes for every port:
`InMemorySystem`, `InMemoryVfs`, `InMemoryTerminal`, `InMemoryLoggerSink`,
`InMemoryMetricsCollector`, plus `expectPortProblem` and
`SeamAssertionFailure`. It imports no test framework, matcher or mocking
package, so it adds nothing to a production dependency graph.

- Every fallible member takes FIFO scripted results (`enqueue…Result`); a
  scripted result is used once, then real fake behaviour resumes.
- `InMemoryTerminal.run` with nothing scripted fails with `unexpected_call`.
- `InMemoryVfs` normalises paths with `InMemoryVfs.normalizePath` (collapse
  empty segments, force a leading `/`).
- `expectPortProblem` checks port, code, status, `recoverable` and, when given,
  the operation, and throws `SeamAssertionFailure` otherwise.

The meta tests prove each fake and assertion fails on a bad interaction and
passes on a good one. The parity suite runs one shared contract per port against
the fakes; no real adapter lives in this package, so adapters re-run that suite
downstream.

## Conformance

`test/conformance/` checks:

- local regression fixtures (`test/fixtures/c0/*.json`, pinned by sha256 in
  `manifest.json`): each port problem is minted, encoded and decoded exactly as
  stored;
- the upstream Problem vectors (`test/fixtures/c0/upstream/`): the envelope
  sample round-trips through the hosted `diene_problems`, port problems use only
  its members, and every port type URI matches the sample template. The
  manifest lists how each vector is adapted.

## Differences from the Bun sibling

| Bun (`@atomicloud/diene.interfaces`)                | Dart                                                          |
| --------------------------------------------------- | ------------------------------------------------------------- |
| `PortError` in `Result<T, E>`                       | `Problem` in `Result<T>`; `PortName` and `PortErrorCode` kept |
| `System.execute`, `ProcessRequest`, `ProcessOutput` | `Terminal.run`, `TerminalCommand`, `TerminalOutput`           |
| no ambient-state port                               | `System`: environment, working directory, clock, delay        |
| `VirtualFileSystem`                                 | `Vfs`                                                         |
| `Checked<T, E>` from validators                     | validators return `Result` directly                           |
| synchronous members                                 | IO members are `Future<Result<T>>`; `emit` stays synchronous  |
| frozen objects                                      | copied, unmodifiable collection views                         |
| `LogLevel.warn`                                     | `LogLevel.warning`                                            |
| `lib/bun/otel` implements logging and metrics       | no OpenTelemetry; Faro in `flutter-base` at runtime           |

Neither family has a trace port. Each code also carries an HTTP status and
`recoverable`, which Bun's `PortError` does not.
