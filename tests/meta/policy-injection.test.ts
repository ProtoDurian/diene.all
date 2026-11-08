import { describe, it } from 'bun:test';
import {
  type Checked,
  type LoggingError,
  LoggingPolicy,
  type LogRecord,
  type MetricRecord,
  type MetricsError,
  MetricsPolicy,
  PortError,
  type ProcessRequest,
  type SystemError,
  SystemPolicy,
  type TerminalError,
  TerminalPolicy,
  type TerminalWrite,
  type VfsError,
  VfsPolicy,
} from '@atomicloud/diene.interfaces';
import {
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InMemorySystem,
  InMemoryTerminal,
  InMemoryVirtualFileSystem,
} from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { expectErr } from './support/capture.js';

class DenyingSystemPolicy extends SystemPolicy {
  override checkRequest(_request: ProcessRequest): Checked<ProcessRequest, SystemError> {
    return { error: new PortError('system', 'permission-denied', 'execute', 'denied'), ok: false };
  }
}

class DenyingVfsPolicy extends VfsPolicy {
  override checkPath(_path: string, operation: string): Checked<string, VfsError> {
    return { error: new PortError('vfs', 'permission-denied', operation, 'denied'), ok: false };
  }
}

class DenyingTerminalPolicy extends TerminalPolicy {
  override checkWrite(_output: TerminalWrite): Checked<Required<TerminalWrite>, TerminalError> {
    return { error: new PortError('terminal', 'permission-denied', 'write', 'denied'), ok: false };
  }
}

class DenyingLoggingPolicy extends LoggingPolicy {
  override checkRecord(_record: LogRecord): Checked<Readonly<LogRecord>, LoggingError> {
    return { error: new PortError('logging', 'permission-denied', 'emit', 'denied'), ok: false };
  }
}

class DenyingMetricsPolicy extends MetricsPolicy {
  override checkRecord(_metric: MetricRecord): Checked<Readonly<MetricRecord>, MetricsError> {
    return { error: new PortError('metrics', 'permission-denied', 'record', 'denied'), ok: false };
  }
}

describe('injected port policies', () => {
  it('should validate System requests with the injected policy and record nothing', async () => {
    // Arrange
    const subject = new InMemorySystem([], new DenyingSystemPolicy());

    // Act
    const error = await expectErr(subject.execute({ executable: 'ls' }));

    // Assert
    error.code.should.eql('permission-denied');
    subject.calls.should.eql([]);
  });

  it('should validate VFS paths with the injected policy and record nothing', async () => {
    // Arrange
    const subject = new InMemoryVirtualFileSystem(new DenyingVfsPolicy());

    // Act
    const error = await expectErr(subject.exists('/a'));

    // Assert
    error.code.should.eql('permission-denied');
    error.operation.should.eql('exists');
    subject.calls.should.eql([]);
  });

  it('should validate Terminal writes with the injected policy and record nothing', async () => {
    // Arrange
    const subject = new InMemoryTerminal([], false, new DenyingTerminalPolicy());

    // Act
    const error = await expectErr(subject.write({ channel: 'stdout', text: 'x' }));

    // Assert
    error.code.should.eql('permission-denied');
    subject.calls.should.eql([]);
  });

  it('should validate log records with the injected policy and record nothing', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink(new DenyingLoggingPolicy());

    // Act
    const error = await expectErr(subject.emit({ level: 'info', message: 'm' }));

    // Assert
    error.code.should.eql('permission-denied');
    subject.records.should.eql([]);
  });

  it('should validate metric records with the injected policy and record nothing', async () => {
    // Arrange
    const subject = new InMemoryMetricsCollector(new DenyingMetricsPolicy());

    // Act
    const error = await expectErr(subject.record({ kind: 'gauge', name: 'temp', value: 1 }));

    // Assert
    error.code.should.eql('permission-denied');
    subject.metrics.should.eql([]);
  });
});
