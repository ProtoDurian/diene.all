import { describe, it } from 'bun:test';
import 'should';
import { RecordTools } from '../../src/lib/record';

describe('RecordTools.isRecord', () => {
  it.each([
    { value: {}, expected: true, label: 'empty object' },
    { value: { a: 1 }, expected: true, label: 'populated object' },
    { value: null, expected: false, label: 'null' },
    { value: [], expected: false, label: 'array' },
    { value: 'text', expected: false, label: 'string' },
    { value: undefined, expected: false, label: 'undefined' },
    { value: () => 1, expected: false, label: 'function' },
  ])('should return $expected for a $label', ({ value, expected }) => {
    // Arrange
    const tools = new RecordTools();

    // Act
    const actual = tools.isRecord(value);

    // Assert
    actual.should.equal(expected);
  });
});

describe('RecordTools.stableConfig', () => {
  it.each([
    {
      label: 'nested records',
      input: { b: 1, a: { d: 4, c: 3 }, list: [3, 1, 2] },
      expected: '{"a":{"c":3,"d":4},"b":1,"list":[3,1,2]}',
    },
    { label: 'records inside arrays', input: [{ y: 2, x: 1 }], expected: '[{"x":1,"y":2}]' },
    { label: 'primitives', input: 42, expected: '42' },
    { label: 'null', input: null, expected: 'null' },
  ])('should sort keys deeply and keep array order for $label', ({ input, expected }) => {
    // Arrange
    const tools = new RecordTools();

    // Act
    const actual = JSON.stringify(tools.stableConfig(input));

    // Assert
    actual.should.equal(expected);
  });

  it('should allow a value shared across sibling branches', () => {
    // Arrange
    const shared = { z: 26, a: 1 };
    const tools = new RecordTools();

    // Act
    const actual = JSON.stringify(tools.stableConfig({ first: shared, second: shared }));

    // Assert
    actual.should.equal('{"first":{"a":1,"z":26},"second":{"a":1,"z":26}}');
  });

  it.each([
    {
      label: 'record',
      make: () => {
        const cyclic: Record<string, unknown> = {};
        cyclic.self = cyclic;
        return cyclic;
      },
    },
    {
      label: 'array',
      make: () => {
        const cyclic: unknown[] = [];
        cyclic.push(cyclic);
        return cyclic;
      },
    },
  ])('should reject a circular $label with a TypeError', ({ make }) => {
    // Arrange
    const tools = new RecordTools();
    const cyclic = make();

    // Act
    const act = () => tools.stableConfig(cyclic);

    // Assert
    act.should.throw(TypeError);
  });
});
