import { describe, it } from 'bun:test';
import 'should';
import type { ILogger } from '../../src/lib/sample/interfaces';
import { Cleanup } from '../../src/lib/sample/cleanup';

const PRIMARY = new Error('the operation blew up');
const SECONDARY = new Error('the disconnect blew up');

function recordingLogger(warnings: string[]): ILogger {
  return {
    info: () => undefined,
    warn: fields => warnings.push(String(fields.reason)),
    error: () => undefined,
  };
}

describe('Cleanup', () => {
  it('should return the operation result and run the cleanup', async () => {
    // Arrange
    const calls: string[] = [];
    const subject = new Cleanup(recordingLogger(calls));

    // Act
    const actual = await subject.run(
      async () => {
        calls.push('operation');
        return 'value';
      },
      async () => {
        calls.push('cleanup');
      },
    );

    // Assert
    actual.should.equal('value');
    calls.should.deepEqual(['operation', 'cleanup']);
  });

  it('should surface a cleanup failure when the operation succeeded', async () => {
    // Arrange
    const warnings: string[] = [];
    const subject = new Cleanup(recordingLogger(warnings));

    // Act
    const actual = subject.run(
      async () => 'value',
      async () => {
        throw SECONDARY;
      },
    );

    // Assert
    await actual.should.be.rejectedWith(SECONDARY);
    warnings.should.deepEqual([]);
  });

  it('should rethrow the operation error after a successful cleanup', async () => {
    // Arrange
    const calls: string[] = [];
    const subject = new Cleanup(recordingLogger(calls));

    // Act
    const actual = subject.run(
      async () => {
        throw PRIMARY;
      },
      async () => {
        calls.push('cleanup');
      },
    );

    // Assert
    await actual.should.be.rejectedWith(PRIMARY);
    calls.should.deepEqual(['cleanup']);
  });

  it('should keep the operation error and log the cleanup failure', async () => {
    // Arrange
    const warnings: string[] = [];
    const subject = new Cleanup(recordingLogger(warnings));

    // Act
    const actual = subject.run(
      async () => {
        throw PRIMARY;
      },
      async () => {
        throw SECONDARY;
      },
    );

    // Assert
    await actual.should.be.rejectedWith(PRIMARY);
    warnings.should.deepEqual([String(SECONDARY)]);
  });

  it('should keep the operation error when logging the cleanup failure also fails', async () => {
    // Arrange
    const subject = new Cleanup({
      info: () => undefined,
      warn: () => {
        throw new Error('logging blew up');
      },
      error: () => undefined,
    });

    // Act
    const actual = subject.run(
      async () => {
        throw PRIMARY;
      },
      async () => {
        throw SECONDARY;
      },
    );

    // Assert
    await actual.should.be.rejectedWith(PRIMARY);
  });
});
