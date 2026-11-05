import { describe, it } from 'bun:test';
import type { LogRecord, MetricRecord, ProcessRequest } from '@atomicloud/diene.interfaces';
import {
  assertLoggerCalls,
  assertLogRecords,
  assertMetricRecords,
  assertMetricsCalls,
  assertSystemCalls,
  assertTerminalCalls,
  assertVfsCalls,
  assertVfsFiles,
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InMemorySystem,
  InMemoryTerminal,
  InMemoryVirtualFileSystem,
  type LoggerCall,
  type MetricsCall,
  type TerminalCall,
  type VfsCall,
} from '@atomicloud/diene.interfaces/test-helper';
import { Ok } from '@atomicloud/diene.result';
import 'should';
import { expectAssertionError, expectNoThrow, expectOk } from './support/capture.js';

describe('assertSystemCalls', () => {
  const arrange = async (): Promise<InMemorySystem> => {
    const subject = new InMemorySystem([Ok({ exitCode: 0, stdout: '', stderr: '' })]);
    await expectOk(subject.execute({ executable: 'ls', arguments: ['-a'] }));
    return subject;
  };
  const expected: readonly ProcessRequest[] = [{ executable: 'ls', arguments: ['-a'] }];

  it('should pass on a matching sequence', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const act = (): void => assertSystemCalls(subject, expected);

    // Assert
    expectNoThrow(act);
  });

  it('should throw a described InterfaceAssertionError on a mismatch', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const error = expectAssertionError(() => assertSystemCalls(subject, [{ executable: 'other' }]));

    // Assert
    error.label.should.eql('System calls');
    error.message.should.match(/System calls mismatch/);
    (error.expected as readonly ProcessRequest[]).should.eql([{ executable: 'other' }]);
    (error.actual as readonly ProcessRequest[]).should.eql([{ executable: 'ls', arguments: ['-a'] }]);
  });
});

describe('assertVfsCalls', () => {
  const arrange = async (): Promise<InMemoryVirtualFileSystem> => {
    const subject = new InMemoryVirtualFileSystem();
    await expectOk(subject.exists('/f'));
    return subject;
  };
  const expected: readonly VfsCall[] = [{ method: 'exists', path: '/f', sequence: 0 }];

  it('should pass on a matching sequence', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const act = (): void => assertVfsCalls(subject, expected);

    // Assert
    expectNoThrow(act);
  });

  it('should throw on a mismatch', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const error = expectAssertionError(() =>
      assertVfsCalls(subject, [{ method: 'exists', path: '/other', sequence: 0 }]),
    );

    // Assert
    error.label.should.eql('VFS calls');
    error.message.should.match(/mismatch/);
  });
});

describe('assertVfsFiles', () => {
  const arrange = async (): Promise<InMemoryVirtualFileSystem> => {
    const subject = new InMemoryVirtualFileSystem();
    await expectOk(subject.writeFile('/f', new Uint8Array([1, 2])));
    return subject;
  };

  it('should pass on matching file bytes', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const act = (): void => assertVfsFiles(subject, { '/f': new Uint8Array([1, 2]) });

    // Assert
    expectNoThrow(act);
  });

  it('should throw on differing bytes', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const error = expectAssertionError(() => assertVfsFiles(subject, { '/f': new Uint8Array([9]) }));

    // Assert
    error.label.should.eql('VFS files');
  });
});

describe('assertTerminalCalls', () => {
  const arrange = async (): Promise<InMemoryTerminal> => {
    const subject = new InMemoryTerminal();
    await expectOk(subject.write({ channel: 'stdout', text: 'hi' }));
    return subject;
  };
  const expected: readonly TerminalCall[] = [
    { method: 'write', output: { channel: 'stdout', text: 'hi', newline: false }, sequence: 0 },
  ];

  it('should pass on a matching sequence', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const act = (): void => assertTerminalCalls(subject, expected);

    // Assert
    expectNoThrow(act);
  });

  it('should throw on a mismatch', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const error = expectAssertionError(() =>
      assertTerminalCalls(subject, [
        { method: 'write', output: { channel: 'stderr', text: 'hi', newline: false }, sequence: 0 },
      ]),
    );

    // Assert
    error.label.should.eql('Terminal calls');
  });
});

describe('assertLogRecords', () => {
  const arrange = async (): Promise<InMemoryLoggerSink> => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit({ level: 'info', message: 'hi' }));
    return subject;
  };
  const expected: readonly LogRecord[] = [{ level: 'info', message: 'hi' }];

  it('should pass on matching records', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const act = (): void => assertLogRecords(subject, expected);

    // Assert
    expectNoThrow(act);
  });

  it('should throw on a mismatch', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const error = expectAssertionError(() => assertLogRecords(subject, [{ level: 'warn', message: 'hi' }]));

    // Assert
    error.label.should.eql('Log records');
  });
});

describe('assertLoggerCalls', () => {
  const arrange = async (): Promise<InMemoryLoggerSink> => {
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit({ level: 'info', message: 'hi' }));
    await expectOk(subject.flush());
    return subject;
  };
  const expected: readonly LoggerCall[] = [
    { method: 'emit', record: { level: 'info', message: 'hi' }, sequence: 0 },
    { method: 'flush', sequence: 1 },
  ];

  it('should pass on a matching call log', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const act = (): void => assertLoggerCalls(subject, expected);

    // Assert
    expectNoThrow(act);
  });

  it('should throw on a mismatch', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const error = expectAssertionError(() => assertLoggerCalls(subject, [{ method: 'flush', sequence: 0 }]));

    // Assert
    error.label.should.eql('Logger calls');
    error.message.should.match(/Logger calls mismatch/);
  });
});

describe('assertMetricRecords', () => {
  const arrange = async (): Promise<InMemoryMetricsCollector> => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.record({ kind: 'counter', name: 'hits', value: 1 }));
    return subject;
  };
  const expected: readonly MetricRecord[] = [{ kind: 'counter', name: 'hits', value: 1 }];

  it('should pass on matching metrics', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const act = (): void => assertMetricRecords(subject, expected);

    // Assert
    expectNoThrow(act);
  });

  it('should throw on a mismatch', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const error = expectAssertionError(() => assertMetricRecords(subject, [{ kind: 'gauge', name: 'hits', value: 1 }]));

    // Assert
    error.label.should.eql('Metric records');
  });
});

describe('assertMetricsCalls', () => {
  const arrange = async (): Promise<InMemoryMetricsCollector> => {
    const subject = new InMemoryMetricsCollector();
    await expectOk(subject.record({ kind: 'counter', name: 'hits', value: 1 }));
    await expectOk(subject.flush());
    return subject;
  };
  const expected: readonly MetricsCall[] = [
    { method: 'record', metric: { kind: 'counter', name: 'hits', value: 1 }, sequence: 0 },
    { method: 'flush', sequence: 1 },
  ];

  it('should pass on a matching call log', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const act = (): void => assertMetricsCalls(subject, expected);

    // Assert
    expectNoThrow(act);
  });

  it('should throw on a mismatch', async () => {
    // Arrange
    const subject = await arrange();

    // Act
    const error = expectAssertionError(() => assertMetricsCalls(subject, [{ method: 'flush', sequence: 0 }]));

    // Assert
    error.label.should.eql('Metrics calls');
    error.message.should.match(/Metrics calls mismatch/);
  });
});
