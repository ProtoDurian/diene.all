import { describe, it } from 'bun:test';
import { type LoggingError, type LogRecord, PortError } from '@atomicloud/diene.interfaces';
import { InMemoryLoggerSink } from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract } from './contract/behaviours.js';
import { expectErr, expectOk } from './support/capture.js';

const ioError = (): LoggingError => new PortError('logging', 'io', 'emit', 'transport down');
const record: LogRecord = { level: 'info', message: 'hello', attributes: { b: 2, a: 1 } };

describe('InMemoryLoggerSink', () => {
  it('should validate, normalize, and retain an emitted record', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();

    // Act
    await expectOk(subject.emit(record));

    // Assert
    subject.records.should.have.length(1);
    Object.keys(subject.records[0]?.attributes ?? {}).should.eql(['a', 'b']);
    subject.calls[0]?.method.should.eql('emit');
  });

  it('should reject an invalid record without retaining it', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();

    // Act
    const error = await expectErr(subject.emit({ level: 'nope' as never, message: 'x' }));

    // Assert
    error.details.should.eql({ field: 'level' });
    subject.records.should.have.length(0);
    subject.calls.should.have.length(0);
  });

  it('should record the emit call but drop the record on an injected failure', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();
    subject.failNext(ioError());

    // Act
    const error = await expectErr(subject.emit({ level: 'warn', message: 'x' }));

    // Assert
    error.code.should.eql('io');
    subject.calls.should.have.length(1);
    subject.calls[0]?.method.should.eql('emit');
    subject.records.should.have.length(0);
  });

  it('should record flush calls and surface flush failures once', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();

    // Act
    await expectOk(subject.flush());
    subject.failNext(ioError());
    const failed = await expectErr(subject.flush());
    await expectOk(subject.flush());

    // Assert
    failed.code.should.eql('io');
    subject.calls.map(call => call.method).should.eql(['flush', 'flush', 'flush']);
  });

  it('should hand back frozen, independent record and call snapshots', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();
    await expectOk(subject.emit(record));

    // Act
    const records = subject.records;
    const firstCallsRead = subject.calls;
    const secondCallsRead = subject.calls;

    // Assert
    Object.isFrozen(records[0]).should.be.true();
    Object.isFrozen(records[0]?.attributes).should.be.true();
    (subject.records[0] === records[0]).should.be.false();
    (firstCallsRead[0] === secondCallsRead[0]).should.be.false();
  });

  it('should satisfy the sequence contract across emit and flush', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();
    let toggle = 0;

    // Assert
    await runSequenceContract({
      label: 'InMemoryLoggerSink',
      record: async () => {
        if (toggle++ % 2 === 0) await subject.emit({ level: 'debug', message: 'm' });
        else await subject.flush();
      },
      sequences: () => subject.calls.map(call => call.sequence),
    });
  });

  it('should satisfy the one-shot fault-injection contract', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();

    // Assert
    await runFailInjectionContract({
      label: 'InMemoryLoggerSink',
      makeError: () => ioError(),
      injectFailure: error => subject.failNext(error),
      callFallible: () => subject.emit({ level: 'info', message: 'm' }),
    });
  });

  it('should satisfy the snapshot isolation contract', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();

    // Assert
    await runSnapshotIsolationContract({
      label: 'InMemoryLoggerSink',
      produce: async () => {
        await subject.emit({ level: 'info', message: 'm' });
      },
      readSnapshot: () => subject.records,
    });
  });
});
