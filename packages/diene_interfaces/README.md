# diene_interfaces

[![pub package](https://img.shields.io/pub/v/diene_interfaces.svg)](https://pub.dev/packages/diene_interfaces)
[![CI](https://github.com/ProtoDurian/diene.dart_interfaces/actions/workflows/ci.yaml/badge.svg)](https://github.com/ProtoDurian/diene.dart_interfaces/actions/workflows/ci.yaml)

Ports between portable Dart code and the host: process state and clock
(`System`), filesystem (`Vfs`), process execution and stdio (`Terminal`), and
log and metric emission (`LoggerSink`, `MetricsCollector`). Every fallible
member returns a [`diene_result`](https://pub.dev/packages/diene_result)
`Result` whose error is a [`diene_problems`](https://pub.dev/packages/diene_problems)
`Problem`; nothing throws for an expected failure.

```dart
import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_result/diene_result.dart';

Future<Result<String>> loadConfig(Vfs vfs, String path) => vfs.readText(path);
```

```dart
import 'package:diene_interfaces/test_helper.dart';

final InMemoryVfs vfs = InMemoryVfs(
  files: <String, List<int>>{'/etc/app.yaml': 'landscape: lapras'.codeUnits},
);
final String text = (await vfs.readText('/etc/app.yaml')).unwrap();
```

## Public surface

- Ports: `System`, `Vfs`, `Terminal`, `LoggerSink`, `MetricsCollector`.
- Values: `VfsEntry`, `VfsEntryType`, `VfsStat`, `TerminalCommand`,
  `TerminalOutput`, `TerminalWrite`, `TerminalRead`, `TerminalChannel`,
  `LogRecord`, `LogLevel`, `MetricRecord`, `MetricKind`, `TelemetryAttributes`.
- Failures: `PortName`, `PortErrorCode`, `portProblem`, `portFailure`,
  `invalidInput`.
- Validators for adapters: `checkVfsPath`, `checkTerminalCommand`,
  `checkTerminalOutput`, `checkTerminalWrite`, `checkTerminalRead`,
  `checkLogRecord`, `checkMetricRecord`, `checkTelemetryAttributes`.

This package has no adapters. Pure helpers live in `diene_core_utils`; real
process, filesystem, terminal and telemetry adapters belong to Flutter or the
app runtime. Dart has no OpenTelemetry package: telemetry goes through Faro in
`flutter-base`.

## TestHelper

`package:diene_interfaces/test_helper.dart` has in-memory fakes for every port
(`InMemorySystem`, `InMemoryVfs`, `InMemoryTerminal`, `InMemoryLoggerSink`,
`InMemoryMetricsCollector`) with FIFO scripted results, plus
`expectPortProblem` and `SeamAssertionFailure`. It pulls in no test framework.

Read the [package doc](doc/diene_interfaces.md) for the full contract.

## Development

- `task setup` resolves the workspace dependencies.
- `task test` runs the unit, conformance and TestHelper meta suites.
- `task test:coverage` enforces the separate unit and meta ledgers.
- `task deadcode` runs the repository and production-only dead-code passes.
- `task package:validate` runs the release guard, publish dry-run and pana.
