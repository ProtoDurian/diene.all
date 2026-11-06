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

  it('should return a sorted clone and leave the input unchanged', () => {
    // Arrange
    const tools = new RecordTools();
    const input = { b: 1, a: { d: 4, c: 3 } };

    // Act
    const actual = tools.stableConfig(input);

    // Assert
    (actual === input).should.be.false();
    Object.keys(input).should.deepEqual(['b', 'a']);
    Object.keys(input.a).should.deepEqual(['d', 'c']);
    JSON.stringify(actual).should.equal('{"a":{"c":3,"d":4},"b":1}');
  });

  it.each([
    { label: 'a Date', make: () => new Date(0) },
    { label: 'a Map', make: () => new Map([[1, 2]]) },
    { label: 'a Set', make: () => new Set([1]) },
    {
      label: 'a class instance',
      make: () =>
        new (class Point {
          constructor(readonly x = 1) {}
        })(),
    },
  ])('should pass $label through unchanged', ({ make }) => {
    // Arrange
    const tools = new RecordTools();
    const value = make();

    // Act
    const actual = tools.stableConfig({ z: 0, value }) as Record<string, unknown>;

    // Assert
    (actual.value === value).should.be.true();
    Object.keys(actual).should.deepEqual(['value', 'z']);
  });

  it('should recurse into a null-prototype object', () => {
    // Arrange
    const tools = new RecordTools();
    const input = Object.assign(Object.create(null) as Record<string, unknown>, { b: 2, a: 1 });

    // Act
    const actual = JSON.stringify(tools.stableConfig(input));

    // Assert
    actual.should.equal('{"a":1,"b":2}');
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
