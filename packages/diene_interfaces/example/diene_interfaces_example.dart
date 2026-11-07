import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';

Future<Result<String>> describeConfig(Vfs vfs, System system) async {
  final Result<String> path = system
      .environment('CONFIG_PATH')
      .andThen(
        (String? value) => value == null
            ? invalidInput<String>(
                port: PortName.system,
                operation: 'environment',
                field: 'CONFIG_PATH',
                message: 'CONFIG_PATH is not set',
              )
            : Ok<String>(value),
      );
  return switch (path) {
    Err<String>() => path,
    Ok<String>(:final String value) => await vfs.readText(value),
  };
}

Future<void> main() async {
  final InMemorySystem system = InMemorySystem(
    environment: <String, String>{'CONFIG_PATH': '/etc/app.yaml'},
  );
  final InMemoryVfs vfs = InMemoryVfs(
    files: <String, List<int>>{'/etc/app.yaml': 'landscape: lapras'.codeUnits},
  );

  final Result<String> found = await describeConfig(vfs, system);
  assert(found.unwrap() == 'landscape: lapras', 'the seam reads the file');

  final Result<String> missing = await describeConfig(
    InMemoryVfs(),
    InMemorySystem(),
  );
  assert(missing.isErr, 'an unset variable is reported as a Problem');

  final InMemoryLoggerSink logger = InMemoryLoggerSink();
  final Result<void> emitted = logger.emit(
    LogRecord(
      timestamp: system.nowUtc().unwrap(),
      level: LogLevel.info,
      message: 'config loaded',
      attributes: <String, Object?>{'path': '/etc/app.yaml'},
    ),
  );
  assert(emitted.isOk, 'the fake accepted the record');
  assert(logger.records.length == 1, 'the fake captured the record');
}
