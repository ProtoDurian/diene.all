import { describe, it } from 'bun:test';
import 'should';
import { AppIdentityBuilder, InMemoryTraceEmitter, OtelAssertionError, OtelAssertions } from '../../src/test-helper';

const assertions = new OtelAssertions();

async function emitted(): Promise<InMemoryTraceEmitter> {
  const emitter = new InMemoryTraceEmitter();
  await emitter.emit({ name: 'work', attributes: { b: 2, a: 1 } }).unwrap();
  await emitter.flush().unwrap();
  return emitter;
}

describe('OtelAssertions.traceRecords', () => {
  it('should pass on the recorded traces whatever the key order', async () => {
    // Arrange
    const emitter = await emitted();

    // Act
    const act = () => assertions.traceRecords(emitter, [{ attributes: { a: 1, b: 2 }, name: 'work' }]);

    // Assert
    act.should.not.throw();
  });

  it('should fail with both sides on a known-bad trace', async () => {
    // Arrange
    const emitter = await emitted();

    // Act
    const act = () => assertions.traceRecords(emitter, [{ name: 'other' }]);

    // Assert
    act.should.throw(OtelAssertionError, { label: 'Trace records', expected: [{ name: 'other' }] });
    act.should.throw(
      /Trace records mismatch\nExpected: \[\{"name":"other"\}\]\nActual: \[\{"attributes":\{"a":1,"b":2\},"name":"work"\}\]/,
    );
  });
});

describe('OtelAssertions.traceCalls', () => {
  it('should pass on the recorded call sequence', async () => {
    // Arrange
    const emitter = await emitted();

    // Act
    const act = () =>
      assertions.traceCalls(emitter, [
        { method: 'emit', record: { name: 'work', attributes: { a: 1, b: 2 } }, sequence: 0 },
        { method: 'flush', sequence: 1 },
      ]);

    // Assert
    act.should.not.throw();
  });

  it('should fail when a flush is missing', async () => {
    // Arrange
    const emitter = await emitted();

    // Act
    const act = () =>
      assertions.traceCalls(emitter, [
        { method: 'emit', record: { name: 'work', attributes: { a: 1, b: 2 } }, sequence: 0 },
      ]);

    // Assert
    act.should.throw(OtelAssertionError, { label: 'Trace calls' });
  });
});

describe('OtelAssertions.resourceAttributes and payload', () => {
  it('should pass on equal attributes and payloads', () => {
    // Arrange
    const attributes = { 'service.name': 'svc', 'atomi.module': 'api' };

    // Act
    const act = () => {
      assertions.resourceAttributes(attributes, { 'atomi.module': 'api', 'service.name': 'svc' });
      assertions.payload([{ x: [1, { y: null }] }], [{ x: [1, { y: null }] }]);
    };

    // Assert
    act.should.not.throw();
  });

  it.each([
    ['a changed attribute', () => assertions.resourceAttributes({ a: 'x' }, { a: 'y' }), 'Resource attributes'],
    ['a payload of another shape', () => assertions.payload({ a: [1] }, { a: [2] }), 'Telemetry payload'],
  ])('should fail on %s', (_label, act, label) => {
    // Arrange
    const run = act;

    // Act
    const attempt = () => run();

    // Assert
    attempt.should.throw(OtelAssertionError, { label });
  });
});

describe('OtelAssertions.identityResource', () => {
  const identity = new AppIdentityBuilder().with({ service: 'checkout' });

  it('should pass when the resource carries the identity, extra attributes allowed', () => {
    // Arrange
    const actual = { ...identity.attributes(), 'host.name': 'box' };

    // Act
    const act = () => assertions.identityResource(actual, identity.build());

    // Assert
    act.should.not.throw();
  });

  it('should fail when an identity attribute is missing', () => {
    // Arrange
    const { 'atomi.module': _dropped, ...actual } = identity.attributes();

    // Act
    const act = () => assertions.identityResource(actual, identity.build());

    // Assert
    act.should.throw(OtelAssertionError, { label: 'Identity resource attributes' });
  });
});

function cyclic(): Record<string, unknown> {
  const value: Record<string, unknown> = {};
  value.self = value;
  return value;
}

describe('OtelAssertions rejects values JSON cannot carry', () => {
  it.each([
    ['NaN against null', { value: Number.NaN }, { value: null }, 'Actual holds a non-JSON value at $.value (NaN)'],
    [
      'an explicit undefined against omission',
      { value: undefined },
      {},
      'Actual holds a non-JSON value at $.value (undefined)',
    ],
    [
      'Infinity on the expected side',
      { value: 1 },
      { value: Number.POSITIVE_INFINITY },
      'Expected holds a non-JSON value at $.value (Infinity)',
    ],
    ['a function inside an array', [() => 1], [null], 'Actual holds a non-JSON value at $[0] (function)'],
    ['a symbol', { s: Symbol('x') }, { s: 'x' }, 'Actual holds a non-JSON value at $.s (symbol)'],
    ['a bigint', { n: 1n }, { n: 1 }, 'Actual holds a non-JSON value at $.n (bigint)'],
    ['a Map', { m: new Map() }, { m: {} }, 'Actual holds a non-JSON value at $.m (non-plain object)'],
    // biome-ignore lint/suspicious/noSparseArray: the hole is the case under test
    ['an array hole against null', [, 1], [null, 1], 'Actual holds a non-JSON value at $[0] (hole)'],
    ['a new Array hole', { a: [1] }, { a: new Array(2) }, 'Expected holds a non-JSON value at $.a[0] (hole)'],
    ['a cycle on the actual side', cyclic(), { self: {} }, 'Actual holds a non-JSON value at $.self (cycle)'],
    ['a cycle on the expected side', { self: {} }, cyclic(), 'Expected holds a non-JSON value at $.self (cycle)'],
    [
      'a cycle through an array',
      { list: [cyclic()] },
      { list: [{}] },
      'Actual holds a non-JSON value at $.list[0].self (cycle)',
    ],
  ])('should fail on %s', (_label, actual, expected, message) => {
    // Arrange
    const run = () => assertions.payload(actual, expected);

    // Act
    const attempt = () => run();

    // Assert
    attempt.should.throw(OtelAssertionError, { label: 'Telemetry payload', message: `Telemetry payload: ${message}` });
  });

  it('should pass on a repeated reference that is not a cycle', () => {
    // Arrange
    const shared = { a: 1 };

    // Act
    const act = () => assertions.payload({ x: shared, y: [shared, shared] }, { x: { a: 1 }, y: [{ a: 1 }, { a: 1 }] });

    // Assert
    act.should.not.throw();
  });

  it('should still pass on equal null-prototype and nested JSON payloads', () => {
    // Arrange
    const actual = Object.assign(Object.create(null), { a: [true, 'x', null, { b: 1.5 }] });

    // Act
    const act = () => assertions.payload(actual, { a: [true, 'x', null, { b: 1.5 }] });

    // Assert
    act.should.not.throw();
  });
});

describe('OtelAssertionError identity', () => {
  class NarrowAssertionError extends OtelAssertionError {}

  it.each([
    ['an OtelAssertionError', new OtelAssertionError('l', 1, 2, 'm'), OtelAssertionError, true],
    [
      'a branded look-alike from the other build',
      { [Symbol.for('AtomiCloud.Diene.Otel.OtelAssertionError')]: true },
      OtelAssertionError,
      true,
    ],
    ['a plain Error', new Error('m'), OtelAssertionError, false],
    ['null', null, OtelAssertionError, false],
    ['a base error against a subclass', new OtelAssertionError('l', 1, 2, 'm'), NarrowAssertionError, false],
    ['a subclass error against the subclass', new NarrowAssertionError('l', 1, 2, 'm'), NarrowAssertionError, true],
  ])('should judge %s', (_label, value, type, expected) => {
    // Arrange
    const candidate: unknown = value;

    // Act
    const actual = candidate instanceof (type as typeof OtelAssertionError);

    // Assert
    actual.should.eql(expected);
  });
});
