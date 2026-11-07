---
name: diene-interfaces-usage
description: Use when consuming package:diene_interfaces — injecting the System, Vfs, Terminal, LoggerSink or MetricsCollector ports, handling their Result failures, or using the in-memory fakes from test_helper.dart in tests.
---

# diene_interfaces usage

The package doc (`doc/diene_interfaces.md`) is authoritative; read it first.
`patterns.md` has short wiring and test examples.

- Import only `package:diene_interfaces/diene_interfaces.dart`; never `lib/src`.
- Take the narrowest port a component needs (a clock is `System`, not
  `Terminal`), passed in through the constructor. Never use `dart:io` in
  portable code; real adapters live in Flutter or the app runtime.
- Every fallible member returns `Result`; handle it with `match`, `andThen` or a
  `switch`, never `try`/`catch`.
- Report your own port failures with `portFailure` or `invalidInput`, never a
  hand-written `Problem`.
- An unset variable is `Ok(null)`; a non-zero exit code is `Ok(TerminalOutput)`.
- No OpenTelemetry here: logs and metrics reach Faro through a Flutter adapter.

## Tests

Import `package:diene_interfaces/test_helper.dart`:

```dart
final InMemoryVfs vfs = InMemoryVfs(files: {'/a.txt': utf8.encode('hi')});
vfs.enqueueReadTextResult(portFailure(
    port: PortName.vfs, code: PortErrorCode.permissionDenied,
    operation: 'readText', message: 'denied'));
expectPortProblem(problem, port: PortName.vfs,
    code: PortErrorCode.permissionDenied, operation: 'readText');
```

`InMemoryTerminal` needs a scripted `enqueue(...)` for each `run`. The helpers
throw `SeamAssertionFailure` and add no test framework to your graph.
