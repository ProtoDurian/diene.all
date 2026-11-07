# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## Unreleased (0.0.0)

No public API or behaviour change from 1.0.0.

- The repository, homepage and issue tracker move to
  `ProtoDurian/diene.dart_interfaces`.
- API doc comments are shorter; the package doc moves to
  `doc/diene_interfaces.md`.
- Conformance tests now check pinned copies of the shared Problem vectors and
  local port-problem fixtures, instead of a generated projection.

## 1.0.0

- Add the ports `System` (environment, working directory, UTC clock, delay),
  `Vfs` (existence, stat, byte and text IO, listing, directory creation,
  deletion), `Terminal` (process execution and line-based stdio), `LoggerSink`
  and `MetricsCollector`.
- Report every expected failure as a `Result` holding a `Problem` from
  `diene_problems`, with the type URI built by `problemTypeUri` (`PortName`,
  `PortErrorCode`, `portProblem`, `portFailure`, `invalidInput`).
- Add validators for adapters: `checkVfsPath`, `checkTerminalCommand`,
  `checkTerminalOutput`, `checkTerminalWrite`, `checkTerminalRead`,
  `checkLogRecord`, `checkMetricRecord` and `checkTelemetryAttributes`.
- Ship `test_helper.dart`: in-memory fakes for every port with FIFO scripted
  results, plus `expectPortProblem` and `SeamAssertionFailure`, with no test
  framework dependency.
- No trace port and no OpenTelemetry implementation: Dart and Flutter telemetry
  goes through Faro at runtime.
