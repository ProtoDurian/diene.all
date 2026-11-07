# diene_interfaces patterns

## Script only the failure under test

A scripted result is used once, in FIFO order; then the fake's real in-memory
behaviour resumes.

```dart
final InMemoryVfs vfs = InMemoryVfs(
  files: <String, List<int>>{'/a.txt': 'ok'.codeUnits},
)..enqueueReadTextResult(
  portFailure<String>(
    port: PortName.vfs,
    code: PortErrorCode.io,
    operation: 'readText',
    message: 'Disk error',
  ),
);

(await vfs.readText('/a.txt')).isErr; // scripted failure
(await vfs.readText('/a.txt')).isOk; // real behaviour again
```

`InMemoryTerminal.run` has no default: unscripted, it fails with
`unexpected_call`. Each fake records what it saw (`requestedDelays`, `commands`,
`writes`, `reads`, `records`, `flushCount`, `files`, `directories`); the
snapshots are unmodifiable.

## Assert port failures

```dart
expectPortProblem(
  expectErr(await vfs.readText('/missing')),
  port: PortName.vfs,
  code: PortErrorCode.notFound,
  operation: 'readText',
);
```

`expectErr` and `expectOk` come from `package:diene_result/test_helper.dart`.

## Re-run the contract suite on a real adapter

`test/meta/contract_parity_test.dart` defines `systemContract`, `vfsContract`,
`terminalContract`, `loggerContract` and `metricsContract`, each taking a label
and a builder. Copy them into the adapter's tests and run them on the adapter:

```dart
void main() {
  vfsContract('LocalVfs', () => LocalVfs(root: tempDir.path));
}
```
