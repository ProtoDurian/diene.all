import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

final String _nul = String.fromCharCode(0);

void main() {
  group('TerminalCommand', () {
    test('copies and freezes its arguments and environment', () {
      // Arrange
      final List<String> arguments = <String>['--version'];
      final Map<String, String> environment = <String, String>{'LC_ALL': 'C'};

      // Act
      final TerminalCommand command = TerminalCommand(
        executable: 'git',
        arguments: arguments,
        environment: environment,
        workingDirectory: '/repo',
        includeParentEnvironment: false,
        runInShell: true,
      );
      arguments.add('--mutated');
      environment['INJECTED'] = '1';
      void mutateArguments() => command.arguments.add('x');
      void mutateEnvironment() => command.environment['x'] = 'y';

      // Assert
      expect(command.arguments, <String>['--version']);
      expect(command.environment, <String, String>{'LC_ALL': 'C'});
      expect(mutateArguments, throwsUnsupportedError);
      expect(mutateEnvironment, throwsUnsupportedError);
      expect(command.workingDirectory, '/repo');
      expect(command.includeParentEnvironment, isFalse);
      expect(command.runInShell, isTrue);
      expect(command.toString(), 'TerminalCommand(git --version)');
    });

    test('defaults to an inherited environment and no shell', () {
      // Arrange
      const String executable = 'ls';

      // Act
      final TerminalCommand command = TerminalCommand(executable: executable);

      // Assert
      expect(command.arguments, isEmpty);
      expect(command.environment, isEmpty);
      expect(command.workingDirectory, isNull);
      expect(command.includeParentEnvironment, isTrue);
      expect(command.runInShell, isFalse);
    });
  });

  group('TerminalOutput', () {
    test('reports success only for a zero exit code', () {
      // Arrange
      const int successExitCode = 0;
      const int failureExitCode = 1;

      // Act
      const TerminalOutput ok = TerminalOutput(
        exitCode: successExitCode,
        stdout: 'out',
        stderr: '',
      );
      const TerminalOutput failed = TerminalOutput(
        exitCode: failureExitCode,
        stdout: '',
        stderr: 'err',
      );

      // Assert
      expect(ok.succeeded, isTrue);
      expect(ok.stdout, 'out');
      expect(failed.succeeded, isFalse);
      expect(failed.stderr, 'err');
      expect(failed.toString(), 'TerminalOutput(1)');
    });
  });

  group('TerminalWrite and TerminalRead', () {
    test('a write defaults to a trailing newline', () {
      // Arrange
      const String text = 'boom';

      // Act
      const TerminalWrite write = TerminalWrite(
        channel: TerminalChannel.stderr,
        text: text,
      );

      // Assert
      expect(write.channel, TerminalChannel.stderr);
      expect(write.newline, isTrue);
      expect(write.toString(), 'TerminalWrite(stderr, 4 chars)');
      expect(TerminalChannel.values, hasLength(2));
    });

    test('a read carries an optional prompt', () {
      // Arrange
      const String prompt = 'name? ';

      // Act
      const TerminalRead read = TerminalRead(prompt: prompt);
      const TerminalRead defaultRead = TerminalRead();

      // Assert
      expect(read.prompt, 'name? ');
      expect(read.toString(), 'TerminalRead(name? )');
      expect(defaultRead.prompt, isNull);
    });
  });

  group('checkTerminalCommand', () {
    test('accepts a well-formed invocation', () {
      // Arrange
      final TerminalCommand command = TerminalCommand(
        executable: 'git',
        arguments: <String>['status'],
        environment: <String, String>{'LC_ALL': 'C'},
      );

      // Act
      final result = checkTerminalCommand(command);

      // Assert
      expect(expectOk(result), same(command));
    });

    test('rejects a blank executable', () {
      // Arrange
      final TerminalCommand command = TerminalCommand(executable: '  ');

      // Act
      final result = checkTerminalCommand(command);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'executable');
      expect(problem.title, 'Executable must be non-blank');
    });

    test('rejects a NUL-bearing executable', () {
      // Arrange
      final TerminalCommand command = TerminalCommand(executable: 'g${_nul}it');

      // Act
      final result = checkTerminalCommand(command);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.title, 'Executable must not contain a NUL byte');
    });

    test('rejects a NUL-bearing argument', () {
      // Arrange
      final TerminalCommand command = TerminalCommand(
        executable: 'git',
        arguments: <String>['ok', 'ba${_nul}d'],
      );

      // Act
      final result = checkTerminalCommand(command);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'arguments');
    });

    test('rejects a blank environment name', () {
      // Arrange
      final TerminalCommand command = TerminalCommand(
        executable: 'git',
        environment: <String, String>{' ': 'x'},
      );

      // Act
      final result = checkTerminalCommand(command);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'environment');
    });

    test('rejects an environment name containing an equals sign', () {
      // Arrange
      final TerminalCommand command = TerminalCommand(
        executable: 'git',
        environment: <String, String>{'A=B': 'x'},
      );

      // Act
      final result = checkTerminalCommand(command);

      // Assert
      final Problem problem = expectErr(result);
      expect(
        problem.title,
        'Environment names must be non-blank and free of "="',
      );
    });
  });

  group('checkTerminalOutput', () {
    test('accepts an in-range exit code', () {
      // Arrange
      const TerminalOutput output = TerminalOutput(
        exitCode: 255,
        stdout: '',
        stderr: '',
      );

      // Act
      final result = checkTerminalOutput(output);

      // Assert
      expect(expectOk(result), same(output));
    });

    test('rejects a negative exit code', () {
      // Arrange
      const TerminalOutput output = TerminalOutput(
        exitCode: -1,
        stdout: '',
        stderr: '',
      );

      // Act
      final result = checkTerminalOutput(output);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.data['field'], 'exitCode');
    });

    test('rejects an out-of-range exit code', () {
      // Arrange
      const TerminalOutput output = TerminalOutput(
        exitCode: 256,
        stdout: '',
        stderr: '',
      );

      // Act
      final result = checkTerminalOutput(output);

      // Assert
      final Problem problem = expectErr(result);
      expect(problem.title, 'Exit code must be within 0..255');
    });
  });

  group('checkTerminalWrite and checkTerminalRead', () {
    test('accept clean payloads', () {
      // Arrange
      const TerminalWrite write = TerminalWrite(
        channel: TerminalChannel.stdout,
        text: 'hi',
      );
      const TerminalRead defaultRead = TerminalRead();
      const TerminalRead promptedRead = TerminalRead(prompt: 'go');

      // Act
      final writeResult = checkTerminalWrite(write);
      final defaultResult = checkTerminalRead(defaultRead);
      final promptedResult = checkTerminalRead(promptedRead);

      // Assert
      expect(expectOk(writeResult).text, 'hi');
      expect(expectOk(defaultResult).prompt, isNull);
      expect(expectOk(promptedResult).prompt, 'go');
    });

    test('reject NUL-bearing payloads', () {
      // Arrange
      final TerminalWrite write = TerminalWrite(
        channel: TerminalChannel.stdout,
        text: 'a${_nul}b',
      );
      final TerminalRead read = TerminalRead(prompt: 'a${_nul}b');

      // Act
      final writeResult = checkTerminalWrite(write);
      final readResult = checkTerminalRead(read);

      // Assert
      expect(expectErr(writeResult).data['field'], 'text');
      expect(expectErr(readResult).data['field'], 'prompt');
    });
  });
}
