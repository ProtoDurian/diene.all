import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryTerminal.run', () {
    test('records commands and serves scripted outputs FIFO', () async {
      // Arrange
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueue(
          const Ok<TerminalOutput>(
            TerminalOutput(exitCode: 0, stdout: 'first', stderr: ''),
          ),
        )
        ..enqueue(
          const Ok<TerminalOutput>(
            TerminalOutput(exitCode: 2, stdout: '', stderr: 'usage'),
          ),
        );

      // Act
      final firstResult = await terminal.run(
        TerminalCommand(executable: 'git'),
      );
      final secondResult = await terminal.run(
        TerminalCommand(executable: 'git', arguments: <String>['bogus']),
      );

      // Assert
      final TerminalOutput first = expectOk(firstResult);
      final TerminalOutput second = expectOk(secondResult);
      expect(first.stdout, 'first');
      expect(second.exitCode, 2);
      expect(
        second.succeeded,
        isFalse,
        reason: 'captured, not a transport failure',
      );
      expect(
        terminal.commands.map((TerminalCommand command) => command.executable),
        <String>['git', 'git'],
      );
      expect(terminal.commands.last.arguments, <String>['bogus']);
    });

    test(
      'an unscripted run is an unexpected-call failure, not a throw',
      () async {
        // Arrange
        final InMemoryTerminal terminal = InMemoryTerminal();
        final TerminalCommand command = TerminalCommand(executable: 'missing');

        // Act
        final firstResult = await terminal.run(command);
        final secondResult = await terminal.run(command);

        // Assert
        expect(expectErr(firstResult), isNotNull);
        expectPortProblem(
          expectErr(secondResult),
          port: PortName.terminal,
          code: PortErrorCode.unexpectedCall,
          operation: 'run',
        );
      },
    );

    test('a scripted launch failure crosses as a value', () async {
      // Arrange
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueue(
          portFailure<TerminalOutput>(
            port: PortName.terminal,
            code: PortErrorCode.permissionDenied,
            operation: 'run',
            message: 'Executable not permitted',
          ),
        );
      final TerminalCommand command = TerminalCommand(executable: 'sudo');

      // Act
      final result = await terminal.run(command);

      // Assert
      expectPortProblem(
        expectErr(result),
        port: PortName.terminal,
        code: PortErrorCode.permissionDenied,
      );
    });
  });

  group('InMemoryTerminal stdio', () {
    test('records writes and succeeds by default', () async {
      // Arrange
      final InMemoryTerminal terminal = InMemoryTerminal();
      const TerminalWrite first = TerminalWrite(
        channel: TerminalChannel.stdout,
        text: 'hello',
      );
      const TerminalWrite second = TerminalWrite(
        channel: TerminalChannel.stderr,
        text: 'oops',
        newline: false,
      );

      // Act
      final firstResult = await terminal.write(first);
      final secondResult = await terminal.write(second);

      // Assert
      expectOk(firstResult);
      expectOk(secondResult);
      expect(terminal.writes.map((TerminalWrite write) => write.text), <String>[
        'hello',
        'oops',
      ]);
      expect(terminal.writes.last.newline, isFalse);
    });

    test('scripts a write failure', () async {
      // Arrange
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueueWriteResult(
          portFailure<void>(
            port: PortName.terminal,
            code: PortErrorCode.closed,
            operation: 'write',
            message: 'Stream closed',
          ),
        );
      const TerminalWrite first = TerminalWrite(
        channel: TerminalChannel.stdout,
        text: 'x',
      );
      const TerminalWrite second = TerminalWrite(
        channel: TerminalChannel.stdout,
        text: 'y',
      );

      // Act
      final rejected = await terminal.write(first);
      final accepted = await terminal.write(second);

      // Assert
      expectPortProblem(
        expectErr(rejected),
        port: PortName.terminal,
        code: PortErrorCode.closed,
      );
      expectOk(accepted);
    });

    test(
      'drains seeded input, then reports end of input as Ok(null)',
      () async {
        // Arrange
        final InMemoryTerminal terminal = InMemoryTerminal(
          input: <String>['alice', 'bob'],
        );

        // Act
        final first = await terminal.readLine();
        final second = await terminal.readLine(
          const TerminalRead(prompt: 'name? '),
        );
        final third = await terminal.readLine();

        // Assert
        expect(expectOk(first), 'alice');
        expect(expectOk(second), 'bob');
        expect(expectOk(third), isNull);
        expect(terminal.reads, hasLength(3));
        expect(terminal.reads[1].prompt, 'name? ');
      },
    );

    test('scripts a read failure', () async {
      // Arrange
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueueReadResult(
          portFailure<String?>(
            port: PortName.terminal,
            code: PortErrorCode.unsupported,
            operation: 'readLine',
            message: 'Not interactive',
          ),
        );

      // Act
      final result = await terminal.readLine();

      // Assert
      expectPortProblem(
        expectErr(result),
        port: PortName.terminal,
        code: PortErrorCode.unsupported,
      );
    });

    test('reports the configured interactivity', () {
      // Arrange
      final InMemoryTerminal defaultTerminal = InMemoryTerminal();
      final InMemoryTerminal noninteractiveTerminal = InMemoryTerminal(
        interactive: false,
      );

      // Act
      final bool defaultInteractive = defaultTerminal.interactive;
      final bool configuredInteractive = noninteractiveTerminal.interactive;

      // Assert
      expect(defaultInteractive, isTrue);
      expect(configuredInteractive, isFalse);
    });
  });
}
