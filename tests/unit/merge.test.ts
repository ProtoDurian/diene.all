import { describe, it } from 'bun:test';
import 'should';
import { type ConfigRecord, DeepMerger } from '../../src/lib/merge.js';

const merger = new DeepMerger();

describe('DeepMerger.merge', () => {
  it.each([
    {
      label: 'scalar keys, override winning',
      base: { a: 1, b: 2 },
      override: { b: 3, c: 4 },
      expected: { a: 1, b: 3, c: 4 },
    },
    {
      label: 'nested objects recursively',
      base: { server: { port: 80, host: 'a' }, flag: false },
      override: { server: { port: 8080 } },
      expected: { server: { port: 8080, host: 'a' }, flag: false },
    },
    {
      label: 'arrays wholesale',
      base: { hosts: ['a', 'b', 'c'] },
      override: { hosts: ['x'] },
      expected: { hosts: ['x'] },
    },
    { label: 'an object with a scalar', base: { a: { nested: 1 } }, override: { a: 5 }, expected: { a: 5 } },
    {
      label: 'a scalar with an object',
      base: { a: 5 },
      override: { a: { nested: 1 } },
      expected: { a: { nested: 1 } },
    },
    { label: 'a value with null', base: { a: { nested: 1 } }, override: { a: null }, expected: { a: null } },
  ])('should merge $label', ({ base, override, expected }) => {
    // Arrange
    const left: ConfigRecord = base;

    // Act
    const actual = merger.merge(left, override);

    // Assert
    actual.should.deepEqual(expected);
  });

  it('should not mutate the inputs', () => {
    // Arrange
    const base: ConfigRecord = { a: { b: 1 } };
    const override: ConfigRecord = { a: { c: 2 } };

    // Act
    merger.merge(base, override);

    // Assert
    base.should.deepEqual({ a: { b: 1 } });
    override.should.deepEqual({ a: { c: 2 } });
  });
});
