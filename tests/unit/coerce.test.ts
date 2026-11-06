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

describe('EnvKeyMatcher.matches', () => {
  it.each([
    { style: 'snake', keys: ['port', 'max_retries'], expected: ['max_retries'] },
    { style: 'pascal', keys: ['port', 'MaxRetries'], expected: ['MaxRetries'] },
    { style: 'camel', keys: ['port', 'maxRetries'], expected: ['maxRetries'] },
    { style: 'kebab', keys: ['port', 'max-retries'], expected: ['max-retries'] },
    { style: 'duplicated', keys: ['maxRetries', 'maxRetries'], expected: ['maxRetries'] },
    { style: 'ambiguous', keys: ['maxRetries', 'max_retries'], expected: ['maxRetries', 'max_retries'] },
    { style: 'absent', keys: ['port'], expected: [] },
  ])('should resolve MAX_RETRIES against a $style key', ({ keys, expected }) => {
    // Arrange
    const segment = 'MAX_RETRIES';

    // Act
    const actual = matcher.matches(keys, segment);

    // Assert
    actual.should.deepEqual(expected);
  });
});

describe('ScalarCoercer.coerceAs', () => {
  it.each([
    { raw: '0123', kind: 'string', expected: '0123' },
    { raw: 'true', kind: 'string', expected: 'true' },
    { raw: '42', kind: 'number', expected: 42 },
    { raw: '4x', kind: 'number', expected: '4x' },
    { raw: 'FALSE', kind: 'boolean', expected: false },
    { raw: '1', kind: 'boolean', expected: '1' },
    { raw: '7', kind: 'array', expected: '7' },
    { raw: '7', kind: 'object', expected: '7' },
    { raw: '7', kind: 'unknown', expected: 7 },
  ] as const)('should coerce "$raw" for a $kind target to $expected', ({ raw, kind, expected }) => {
    // Arrange
    const input = raw;

    // Act
    const actual: unknown = coercer.coerceAs(input, kind);

    // Assert
    (actual as object).should.equal(expected);
  });

  it('should treat a blank value as unset for a string target', () => {
    // Arrange
    const raw = '';

    // Act
    const actual = coercer.coerceAs(raw, 'string');

    // Assert
    should(actual).be.undefined();
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
    const actual: unknown = coercer.coerce(input);

    // Assert
    (actual as object).should.equal(expected);
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
