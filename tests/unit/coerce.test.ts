import { describe, it } from 'bun:test';
import should from 'should';
import { EnvKeyMatcher, ScalarCoercer } from '../../src/lib/coerce.js';

const matcher = new EnvKeyMatcher();
const coercer = new ScalarCoercer();

describe('EnvKeyMatcher.normalize', () => {
  it.each([
    { input: 'maxRetries', expected: 'maxretries' },
    { input: 'MAX_RETRIES', expected: 'maxretries' },
    { input: 'MaxRetries', expected: 'maxretries' },
    { input: 'max-retries', expected: 'maxretries' },
    { input: 'max_retries', expected: 'maxretries' },
    { input: 'port', expected: 'port' },
  ])('should normalize "$input" to "$expected"', ({ input, expected }) => {
    // Arrange
    const key = input;

    // Act
    const actual = matcher.normalize(key);

    // Assert
    actual.should.equal(expected);
  });
});

describe('EnvKeyMatcher.match', () => {
  it.each([
    { style: 'snake', keys: ['port', 'max_retries'], expected: 'max_retries' },
    { style: 'pascal', keys: ['port', 'MaxRetries'], expected: 'MaxRetries' },
    { style: 'camel', keys: ['port', 'maxRetries'], expected: 'maxRetries' },
    { style: 'kebab', keys: ['port', 'max-retries'], expected: 'max-retries' },
    { style: 'absent', keys: ['port'], expected: 'max_retries' },
  ])('should resolve MAX_RETRIES against a $style key', ({ keys, expected }) => {
    // Arrange
    const segment = 'MAX_RETRIES';

    // Act
    const actual = matcher.match(keys, segment);

    // Assert
    actual.should.equal(expected);
  });
});

describe('ScalarCoercer.coerce', () => {
  it.each([
    { raw: 'true', expected: true },
    { raw: 'TRUE', expected: true },
    { raw: 'True', expected: true },
    { raw: 'false', expected: false },
    { raw: 'FALSE', expected: false },
    { raw: '0', expected: 0 },
    { raw: '42', expected: 42 },
    { raw: '-7', expected: -7 },
    { raw: '3.14', expected: 3.14 },
    { raw: 'hello', expected: 'hello' },
    { raw: 'v1.2.3', expected: 'v1.2.3' },
    { raw: '8080abc', expected: '8080abc' },
    { raw: '1e3', expected: '1e3' },
    { raw: '{"json":true}', expected: '{"json":true}' },
    { raw: 'a,b', expected: 'a,b' },
  ])('should coerce "$raw" to $expected', ({ raw, expected }) => {
    // Arrange
    const input = raw;

    // Act
    const actual = coercer.coerce(input);

    // Assert
    should(actual).equal(expected);
  });

  it('should treat a blank value as unset', () => {
    // Arrange
    const raw = '';

    // Act
    const actual = coercer.coerce(raw);

    // Assert
    should(actual).be.undefined();
  });
});
