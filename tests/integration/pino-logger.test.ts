import { describe, it } from 'bun:test';
import 'should';
import { PinoLogger, type PinoLoggerConfig } from '../../src/adapters/pino-logger';

interface CapturedRecord {
  readonly msg: string;
  readonly level: number;
  readonly field?: string;
}

function captureDestination(sink: string[]): PinoLoggerConfig['destination'] {
  return {
    write: (line: string) => {
      sink.push(line);
    },
  };
}

function records(sink: readonly string[]): CapturedRecord[] {
  return sink.map(line => JSON.parse(line) as CapturedRecord);
}

describe('PinoLogger', () => {
  it('should keep loggers independent so there is no shared mutable state', () => {
    // Arrange
    const first: string[] = [];
    const second: string[] = [];
    const subject = new PinoLogger({ destination: captureDestination(first) });
    const other = new PinoLogger({ destination: captureDestination(second), level: 'error' });

    // Act
    subject.info({}, 'only first');
    other.info({}, 'dropped by the second logger level');

    // Assert
    records(first)
      .map(record => record.msg)
      .should.deepEqual(['only first']);
    second.should.deepEqual([]);
  });

  it('should write to stdout when no configuration is supplied', () => {
    // Arrange
    const subject = new PinoLogger();

    // Act
    const act = () => subject.info({}, 'stdout logger');

    // Assert
    act.should.not.throw();
  });

  it.each([
    { method: 'info' as const, expected: 30 },
    { method: 'warn' as const, expected: 40 },
    { method: 'error' as const, expected: 50 },
  ])('should emit $method records at pino level $expected', ({ method, expected }) => {
    // Arrange
    const sink: string[] = [];
    const subject = new PinoLogger({ destination: captureDestination(sink), level: 'debug' });

    // Act
    subject[method]({ field: 'value' }, `${method} message`);

    // Assert
    records(sink)
      .map(({ level, msg, field }) => ({ level, msg, field }))
      .should.deepEqual([{ level: expected, msg: `${method} message`, field: 'value' }]);
  });
});
