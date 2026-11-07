import { describe, it } from 'bun:test';
import { PortError } from '@atomicloud/diene.interfaces';
import {
  InMemoryLoggerSink,
  InMemoryTerminal,
  InMemoryVirtualFileSystem,
} from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { expectErr, expectOk } from './support/capture.js';

// Leave each `pending` un-awaited until Assert: the mock must settle it at invocation.

describe('mock linearization', () => {
  it('should record a terminal read synchronously, before the Result is awaited', async () => {
    // Arrange
    const subject = new InMemoryTerminal(['a']);

    // Act
    const pending = subject.readLine({ prompt: 'p' });
    subject.enqueue('late');
    subject.close();

    // Assert
    subject.calls.should.have.length(1);
    subject.calls[0]?.method.should.eql('readLine');
    ((await expectOk(pending)) ?? '').should.eql('a');
    (await expectErr(subject.readLine())).code.should.eql('closed');
  });

  it('should fix a terminal write outcome at call time despite a later close', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Act
    const pending = subject.write({ channel: 'stdout', text: 'hi' });
    subject.close();

    // Assert
    subject.calls.should.have.length(1);
    await expectOk(pending);
  });

  it('should fix a VFS read outcome before a later failNext takes effect', async () => {
    // Arrange
    const subject = new InMemoryVirtualFileSystem();
    await expectOk(subject.writeFile('/f', new Uint8Array([1])));

    // Act
    const pending = subject.exists('/f');
    subject.failNext(new PortError('vfs', 'io', 'exists', 'late fault'));

    // Assert
    (await expectOk(pending)).should.be.true();
    (await expectErr(subject.exists('/f'))).code.should.eql('io');
  });

  it('should retain an emitted log record synchronously, unaffected by a later failNext', async () => {
    // Arrange
    const subject = new InMemoryLoggerSink();

    // Act
    const pending = subject.emit({ level: 'info', message: 'm' });
    subject.failNext(new PortError('logging', 'io', 'emit', 'late fault'));

    // Assert
    subject.calls.should.have.length(1);
    await expectOk(pending);
    subject.records.should.have.length(1);
    (await expectErr(subject.emit({ level: 'info', message: 'n' }))).code.should.eql('io');
  });
});
