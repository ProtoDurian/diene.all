import { describe, it } from 'bun:test';
import 'should';
import { EnvOverrides, NESTING_SEPARATOR } from '../../src/lib/env.js';
import type { ConfigRecord } from '../../src/lib/merge.js';

const PREFIX = 'ATOMI_';
const overrides = new EnvOverrides();

describe('NESTING_SEPARATOR', () => {
  it('should be the double underscore', () => {
    // Arrange
    const expected = '__';

    // Act
    const actual = NESTING_SEPARATOR;

    // Assert
    actual.should.equal(expected);
  });
});

describe('EnvOverrides.apply — name matching', () => {
  it.each([
    { style: 'snake', key: 'max_retries' },
    { style: 'pascal', key: 'MaxRetries' },
    { style: 'camel', key: 'maxRetries' },
    { style: 'kebab', key: 'max-retries' },
  ])('should match a snake env segment onto a $style key', ({ key }) => {
    // Arrange
    const base: ConfigRecord = { server: { [key]: 1 } };

    // Act
    const actual = overrides.apply(base, { ATOMI_SERVER__MAX_RETRIES: '9' }, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { [key]: 9 } });
  });

  it.each([
    'ATOMI_SERVER__MAX_RETRIES',
    'ATOMI_SERVER__MAXRETRIES',
    'ATOMI_server__max_retries',
    'ATOMI_Server__Max-Retries',
  ])('should match %s onto the existing camelCase key', envKey => {
    // Arrange
    const base: ConfigRecord = { server: { maxRetries: 1 } };

    // Act
    const actual = overrides.apply(base, { [envKey]: '9' }, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { maxRetries: 9 } });
  });

  it('should lowercase a segment that matches no existing key', () => {
    // Arrange
    const base: ConfigRecord = {};

    // Act
    const actual = overrides.apply(base, { ATOMI_SERVER__HOST: 'h' }, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { host: 'h' } });
  });
});

describe('EnvOverrides.apply — coercion and unset', () => {
  it('should coerce booleans and numbers', () => {
    // Arrange
    const base: ConfigRecord = { server: { port: 80, debug: false } };

    // Act
    const actual = overrides.apply(base, { ATOMI_SERVER__PORT: '8080', ATOMI_SERVER__DEBUG: 'true' }, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { port: 8080, debug: true } });
  });

  it.each([
    { label: 'a blank value', env: { ATOMI_SERVER__HOST: '' } },
    { label: 'an undefined value', env: { ATOMI_SERVER__HOST: undefined } },
    { label: 'an unprefixed key', env: { OTHER__SERVER__HOST: 'x' } },
    { label: 'a trailing separator', env: { ATOMI_SERVER__: 'x' } },
    { label: 'an empty middle segment', env: { ATOMI_SERVER____HOST: 'x' } },
    { label: 'a bare prefix', env: { ATOMI_: 'x' } },
  ])('should leave the target unchanged for $label', ({ env }) => {
    // Arrange
    const base: ConfigRecord = { server: { host: 'keep' } };

    // Act
    const actual = overrides.apply(base, env, PREFIX);

    // Assert
    actual.should.deepEqual({ server: { host: 'keep' } });
  });
});

describe('EnvOverrides.apply — nesting and indexed lists', () => {
  it.each([
    { label: 'a new nested object', base: {}, env: { ATOMI_A__B__C: '1' }, expected: { a: { b: { c: 1 } } } },
    {
      label: 'an existing array by index',
      base: { endpoints: ['zero', 'one'] },
      env: { ATOMI_ENDPOINTS__0: 'primary', ATOMI_ENDPOINTS__2: 'third' },
      expected: { endpoints: ['primary', 'one', 'third'] },
    },
    {
      label: 'a fresh array',
      base: {},
      env: { ATOMI_LIST__0: 'a', ATOMI_LIST__1: 'b' },
      expected: { list: ['a', 'b'] },
    },
    {
      label: 'an object inside a fresh array',
      base: {},
      env: { ATOMI_ITEMS__0__NAME: 'first' },
      expected: { items: [{ name: 'first' }] },
    },
    {
      label: 'an object inside an existing array',
      base: { items: [{ name: 'a', port: 1 }] },
      env: { ATOMI_ITEMS__0__PORT: '2' },
      expected: { items: [{ name: 'a', port: 2 }] },
    },
    { label: 'a scalar replaced by an object', base: { a: 1 }, env: { ATOMI_A__B: 'x' }, expected: { a: { b: 'x' } } },
    {
      label: 'a non-numeric segment into an array',
      base: { list: ['a'] },
      env: { ATOMI_LIST__FOO: 'x' },
      expected: { list: ['a'] },
    },
    { label: 'an index past the bound', base: { list: [] }, env: { ATOMI_LIST__5000: 'x' }, expected: { list: [] } },
  ])('should handle $label', ({ base, env, expected }) => {
    // Arrange
    const target: ConfigRecord = base;

    // Act
    const actual = overrides.apply(target, env, PREFIX);

    // Assert
    actual.should.deepEqual(expected);
  });

  it('should not mutate the input object', () => {
    // Arrange
    const base: ConfigRecord = { server: { port: 80 } };

    // Act
    overrides.apply(base, { ATOMI_SERVER__PORT: '9090' }, PREFIX);

    // Assert
    base.should.deepEqual({ server: { port: 80 } });
  });
});
