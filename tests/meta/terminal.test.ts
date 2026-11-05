import { describe, it } from 'bun:test';
import { PortError, type TerminalChannel, type TerminalError } from '@atomicloud/diene.interfaces';
import { InMemoryTerminal } from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract } from './contract/behaviours.js';
import { expectErr, expectOk } from './support/capture.js';

const ioError = (operation: string): TerminalError => new PortError('terminal', 'io', operation, 'boom');
const write = { channel: 'stdout', text: 'hi' } as const;

describe('InMemoryTerminal write', () => {
  it('should normalize and record a valid write', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Act
    await expectOk(subject.write({ channel: 'stderr', text: 'x', newline: true }));

    // Assert
    subject.calls[0]?.method.should.eql('write');
    if (subject.calls[0]?.method === 'write') {
      subject.calls[0].output.should.eql({ channel: 'stderr', text: 'x', newline: true });
    }
  });

  it('should reject an invalid channel', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Act
    const error = await expectErr(subject.write({ channel: 'bad' as unknown as TerminalChannel, text: 'x' }));

    // Assert
    error.details.should.eql({ field: 'channel' });
  });

  it('should surface a closed terminal ahead of any injected failure', async () => {
    // Arrange
    const subject = new InMemoryTerminal();
    subject.failNext(ioError('write'));
    subject.close();

    // Act
    const error = await expectErr(subject.write(write));

    // Assert
    error.code.should.eql('closed');
  });

  it('should surface an injected failure while open', async () => {
    // Arrange
    const subject = new InMemoryTerminal();
    subject.failNext(ioError('write'));

    // Act
    const error = await expectErr(subject.write(write));

    // Assert
    error.code.should.eql('io');
  });
});

describe('InMemoryTerminal readLine', () => {
  it('should reject invalid setup values before they can fabricate terminal output', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Act
    const nonStringSeed = (): InMemoryTerminal => new InMemoryTerminal([42 as unknown as string]);
    const nullSeed = (): InMemoryTerminal => new InMemoryTerminal(null as unknown as readonly string[]);
    const nonBooleanInteractive = (): InMemoryTerminal => new InMemoryTerminal([], 'yes' as unknown as boolean);
    const nonStringEnqueue = (): void => subject.enqueue(42 as unknown as string);

    // Assert
    nonStringSeed.should.throw(TypeError);
    nullSeed.should.throw(TypeError);
    nonBooleanInteractive.should.throw(TypeError);
    nonStringEnqueue.should.throw(TypeError);
    const drained = await expectOk(subject.readLine());
    (drained === null).should.be.true();
  });

  it('should default the interactive flag to false and take no argument', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Act
    await expectOk(subject.readLine());

    // Assert
    subject.interactive.should.be.false();
    subject.calls[0]?.method.should.eql('readLine');
    if (subject.calls[0]?.method === 'readLine') subject.calls[0].input.should.eql({});
  });

  it('should drain queued input then return null, honoring constructor seed', async () => {
    // Arrange
    const subject = new InMemoryTerminal(['first'], true);
    subject.enqueue('second');

    // Act
    const first = await expectOk(subject.readLine({ prompt: 'p' }));
    const second = await expectOk(subject.readLine());
    const drained = await expectOk(subject.readLine());

    // Assert
    subject.interactive.should.be.true();
    (first ?? '').should.eql('first');
    (second ?? '').should.eql('second');
    (drained === null).should.be.true();
  });

  it('should reject a non-string prompt', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Act
    const error = await expectErr(subject.readLine({ prompt: 5 as unknown as string }));

    // Assert
    error.details.should.eql({ field: 'prompt' });
  });

  it('should surface a closed terminal', async () => {
    // Arrange
    const subject = new InMemoryTerminal();
    subject.close();

    // Act
    const error = await expectErr(subject.readLine());

    // Assert
    error.code.should.eql('closed');
  });

  it('should surface an injected failure while open', async () => {
    // Arrange
    const subject = new InMemoryTerminal();
    subject.failNext(ioError('readLine'));

    // Act
    const error = await expectErr(subject.readLine());

    // Assert
    error.code.should.eql('io');
  });
});

describe('InMemoryTerminal recorded state', () => {
  it('should expose frozen, independent copies of write and read calls', async () => {
    // Arrange
    const subject = new InMemoryTerminal(['line']);
    await expectOk(subject.write(write));
    await expectOk(subject.readLine({ prompt: 'p' }));

    // Act
    const calls = subject.calls;

    // Assert
    calls.should.have.length(2);
    Object.isFrozen(calls[0]).should.be.true();
    (subject.calls[0] === calls[0]).should.be.false();
  });

  it('should satisfy the sequence contract', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Assert
    await runSequenceContract({
      label: 'InMemoryTerminal',
      record: async () => {
        await subject.readLine();
      },
      sequences: () => subject.calls.map(call => call.sequence),
    });
  });

  it('should satisfy the one-shot fault-injection contract', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Assert
    await runFailInjectionContract({
      label: 'InMemoryTerminal',
      makeError: () => ioError('write'),
      injectFailure: error => subject.failNext(error),
      callFallible: () => subject.write(write),
    });
  });

  it('should satisfy the snapshot isolation contract', async () => {
    // Arrange
    const subject = new InMemoryTerminal();

    // Assert
    await runSnapshotIsolationContract({
      label: 'InMemoryTerminal',
      produce: async () => {
        await subject.readLine();
      },
      readSnapshot: () => subject.calls,
    });
  });
});
