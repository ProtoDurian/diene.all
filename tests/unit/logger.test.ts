import { describe, it } from 'bun:test';
import should from 'should';
import { createLogger, type ILogger, type LoggerConfig } from '../../src/lib/logger';

interface CapturedRecord {
  readonly msg: string;
  readonly level: number;
}

function captureDestination(sink: string[]): LoggerConfig['destination'] {
  return {
    write: (line: string) => {
      sink.push(line);
    },
  };
}

function records(sink: readonly string[]): CapturedRecord[] {
  return sink.map(line => JSON.parse(line) as CapturedRecord);
}

describe('createLogger', () => {
  it('should return an independent logger on every call so there is no shared mutable state', () => {
    const first: string[] = [];
    const second: string[] = [];

    const subject = createLogger({ destination: captureDestination(first) });
    const other = createLogger({ destination: captureDestination(second), level: 'error' });
    subject.info({}, 'only first');
    other.info({}, 'dropped by the second logger level');

    should(records(first).map(record => record.msg)).eql(['only first']);
    should(second).eql([]);
  });

  it('should build a stdout logger when no configuration is supplied', () => {
    const actual = createLogger();

    should(typeof actual.info).equal('function');
    should(typeof actual.warn).equal('function');
    should(typeof actual.error).equal('function');
  });

  it.each([
    { method: 'info' as const, expected: 30 },
    { method: 'warn' as const, expected: 40 },
    { method: 'error' as const, expected: 50 },
  ])('should emit $method records at pino level $expected', ({ method, expected }) => {
    const sink: string[] = [];
    const subject: ILogger = createLogger({ destination: captureDestination(sink), level: 'debug' });

    subject[method]({ field: 'value' }, `${method} message`);

    const [actual] = records(sink);
    should(actual?.level).equal(expected);
    should(actual?.msg).equal(`${method} message`);
  });
});
