import { describe, it } from 'bun:test';
import 'should';
import { RedisConfigParser } from '../../src/lib/sample/config';

const DEFAULT_PORT = 6379;

describe('RedisConfigParser', () => {
  it.each([
    { label: 'no variables at all', input: {} },
    { label: 'an empty host', input: { REDIS_HOST: '' } },
    { label: 'a whitespace-only host', input: { REDIS_HOST: '   ' } },
    { label: 'a tab-only host', input: { REDIS_HOST: '\t\n' } },
    { label: 'an explicitly undefined host', input: { REDIS_HOST: undefined } },
    { label: 'a port but no host', input: { REDIS_PORT: '6380' } },
  ])('should report no connection for $label', ({ input }) => {
    // Arrange
    const subject = new RedisConfigParser(input);

    // Act
    const actual = subject.parse();

    // Assert
    actual.should.deepEqual({ ok: true, connection: undefined });
  });

  it.each([
    { label: 'an unset port', input: { REDIS_HOST: 'cache' }, expected: DEFAULT_PORT },
    { label: 'a blank port', input: { REDIS_HOST: 'cache', REDIS_PORT: '   ' }, expected: DEFAULT_PORT },
    { label: 'an explicit port', input: { REDIS_HOST: 'cache', REDIS_PORT: '6380' }, expected: 6380 },
    { label: 'a padded port', input: { REDIS_HOST: 'cache', REDIS_PORT: ' 6380 ' }, expected: 6380 },
    { label: 'the lowest port', input: { REDIS_HOST: 'cache', REDIS_PORT: '1' }, expected: 1 },
    { label: 'the highest port', input: { REDIS_HOST: 'cache', REDIS_PORT: '65535' }, expected: 65535 },
  ])('should resolve $label to port $expected', ({ input, expected }) => {
    // Arrange
    const subject = new RedisConfigParser(input);

    // Act
    const actual = subject.parse();

    // Assert
    actual.should.deepEqual({ ok: true, connection: { host: 'cache', port: expected } });
  });

  it('should trim surrounding whitespace from the host', () => {
    // Arrange
    const subject = new RedisConfigParser({ REDIS_HOST: '  cache  ' });
    const expected = { ok: true, connection: { host: 'cache', port: DEFAULT_PORT } };

    // Act
    const actual = subject.parse();

    // Assert
    actual.should.deepEqual(expected);
  });

  it.each([
    { input: { REDIS_PORT: 'abc' }, expected: 'REDIS_PORT must be a whole number, for example 6379' },
    { input: { REDIS_PORT: '6379.5' }, expected: 'REDIS_PORT must be a whole number, for example 6379' },
    { input: { REDIS_PORT: '-1' }, expected: 'REDIS_PORT must be a whole number, for example 6379' },
    { input: { REDIS_PORT: '0' }, expected: 'REDIS_PORT must be between 1 and 65535' },
    { input: { REDIS_PORT: '65536' }, expected: 'REDIS_PORT must be between 1 and 65535' },
    { input: { REDIS_HOST: 'cache', REDIS_PORT: '0' }, expected: 'REDIS_PORT must be between 1 and 65535' },
  ])('should reject REDIS_PORT "$input.REDIS_PORT" with a named issue', ({ input, expected }) => {
    // Arrange
    const subject = new RedisConfigParser(input);

    // Act
    const actual = subject.parse();

    // Assert
    actual.should.deepEqual({ ok: false, issues: [expected] });
  });
});
