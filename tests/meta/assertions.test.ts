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
