import 'dart:collection';

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';

final class TerminalCommand {
  /// [arguments] and [environment] are copied and exposed unmodifiable.
  TerminalCommand({
    required this.executable,
    List<String> arguments = const <String>[],
    this.workingDirectory,
    Map<String, String> environment = const <String, String>{},
    this.includeParentEnvironment = true,
    this.runInShell = false,
  }) : arguments = UnmodifiableListView<String>(List<String>.of(arguments)),
       environment = UnmodifiableMapView<String, String>(
         Map<String, String>.of(environment),
       );

  final String executable;

  final List<String> arguments;

  /// The parent's directory when `null`.
  final String? workingDirectory;

  /// Entries layered over the inherited environment.
  final Map<String, String> environment;

  final bool includeParentEnvironment;

  final bool runInShell;

  @override
  String toString() => 'TerminalCommand($executable ${arguments.join(' ')})';
}

final class TerminalOutput {
  const TerminalOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;

  final String stdout;

  final String stderr;

  bool get succeeded => exitCode == 0;

  @override
  String toString() => 'TerminalOutput($exitCode)';
}

enum TerminalChannel { stdout, stderr }

final class TerminalWrite {
  const TerminalWrite({
    required this.channel,
    required this.text,
    this.newline = true,
  });

  final TerminalChannel channel;

  final String text;

  final bool newline;

  @override
  String toString() => 'TerminalWrite(${channel.name}, ${text.length} chars)';
}

final class TerminalRead {
  const TerminalRead({this.prompt});

  final String? prompt;

  @override
  String toString() => 'TerminalRead($prompt)';
}

/// Runs processes and does line-based stdio.
abstract interface class Terminal {
  /// When false, `readLine` returns `Ok(null)` at end of input, never blocks.
  bool get interactive;

  /// A non-zero exit code is `Ok`; only a launch failure is `Err`.
  Future<Result<TerminalOutput>> run(TerminalCommand command);

  Future<Result<void>> write(TerminalWrite output);

  /// `Ok(null)` at end of input.
  Future<Result<String?>> readLine([TerminalRead input = const TerminalRead()]);
}

Result<TerminalCommand> checkTerminalCommand(
  TerminalCommand command, {
  String operation = 'run',
}) {
  if (command.executable.trim().isEmpty) {
    return invalidInput<TerminalCommand>(
      port: PortName.terminal,
      operation: operation,
      field: 'executable',
      message: 'Executable must be non-blank',
    );
  }
  if (command.executable.codeUnits.contains(0)) {
    return invalidInput<TerminalCommand>(
      port: PortName.terminal,
      operation: operation,
      field: 'executable',
      message: 'Executable must not contain a NUL byte',
    );
  }
  for (final String argument in command.arguments) {
    if (argument.codeUnits.contains(0)) {
      return invalidInput<TerminalCommand>(
        port: PortName.terminal,
        operation: operation,
        field: 'arguments',
        message: 'Arguments must not contain a NUL byte',
      );
    }
  }
  for (final String name in command.environment.keys) {
    if (name.trim().isEmpty || name.contains('=')) {
      return invalidInput<TerminalCommand>(
        port: PortName.terminal,
        operation: operation,
        field: 'environment',
        message: 'Environment names must be non-blank and free of "="',
      );
    }
  }
  return Ok<TerminalCommand>(command);
}

/// Rejects exit codes outside 0..255.
Result<TerminalOutput> checkTerminalOutput(
  TerminalOutput output, {
  String operation = 'run',
}) {
  if (output.exitCode < 0 || output.exitCode > 255) {
    return invalidInput<TerminalOutput>(
      port: PortName.terminal,
      operation: operation,
      field: 'exitCode',
      message: 'Exit code must be within 0..255',
    );
  }
  return Ok<TerminalOutput>(output);
}

Result<TerminalWrite> checkTerminalWrite(
  TerminalWrite output, {
  String operation = 'write',
}) {
  if (output.text.codeUnits.contains(0)) {
    return invalidInput<TerminalWrite>(
      port: PortName.terminal,
      operation: operation,
      field: 'text',
      message: 'Text must not contain a NUL byte',
    );
  }
  return Ok<TerminalWrite>(output);
}

Result<TerminalRead> checkTerminalRead(
  TerminalRead input, {
  String operation = 'readLine',
}) {
  final String? prompt = input.prompt;
  if (prompt != null && prompt.codeUnits.contains(0)) {
    return invalidInput<TerminalRead>(
      port: PortName.terminal,
      operation: operation,
      field: 'prompt',
      message: 'Prompt must not contain a NUL byte',
    );
  }
  return Ok<TerminalRead>(input);
}
