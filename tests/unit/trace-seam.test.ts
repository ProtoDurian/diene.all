import { describe, it } from 'bun:test';
import 'should';
import { TraceError, TraceRecordValidator } from '../../src/lib/trace-seam';

const validator = new TraceRecordValidator();

describe('TraceError', () => {
  it('should carry its code, operation and frozen details', () => {
    // Arrange
    const details = { cause: 'x' };

    // Act
    const actual = new TraceError('io', 'flush', 'failed', details);

    // Assert
    actual.should.match({ name: 'TraceError', _tag: 'TraceError', code: 'io', operation: 'flush', message: 'failed' });
    actual.details.should.eql(details);
    Object.isFrozen(actual.details).should.be.true();
  });

  it('should default details to an empty record', () => {
    // Arrange
    const message = 'failed';

    // Act
    const actual = new TraceError('io', 'emit', message);

    // Assert
    actual.details.should.eql({});
  });

  it.each([
    ['a TraceError', new TraceError('io', 'emit', 'x'), true],
    [
      'a branded look-alike from another bundle',
      Object.assign({}, { [Symbol.for('AtomiCloud.Diene.Otel.TraceError')]: true }),
      true,
    ],
    ['a plain Error', new Error('x'), false],
    ['null', null, false],
    ['a string', 'TraceError', false],
  ])('should treat %s as an instance: %s', (_label, value, expected) => {
    // Arrange
    const candidate: unknown = value;

    // Act
    const actual = candidate instanceof TraceError;

    // Assert
    actual.should.eql(expected);
  });
});

describe('TraceRecordValidator.record', () => {
  it('should normalise a valid record with sorted, frozen attributes', () => {
    // Arrange
    const record = {
      name: 'checkout',
      attributes: { z: 1, a: 'x', m: true },
      events: [{ name: 'paid', attributes: { amount: 3 } }, { name: 'shipped' }],
      status: 'ok' as const,
      statusMessage: 'done',
    };

    // Act
    const actual = validator.record(record);

    // Assert
    actual.ok.should.be.true();
    if (!actual.ok) return;
    Object.keys(actual.value.attributes ?? {}).should.eql(['a', 'm', 'z']);
    actual.value.should.eql(record);
    Object.isFrozen(actual.value).should.be.true();
  });

  it('should keep a minimal record minimal', () => {
    // Arrange
    const record = { name: 'bare', events: [] };

    // Act
    const actual = validator.record(record);

    // Assert
    actual.should.eql({ ok: true, value: { name: 'bare' } });
  });

  it.each([
    ['a non-object', 'x', 'Trace record must be an object'],
    ['null', null, 'Trace record must be an object'],
    ['a blank name', { name: ' ' }, 'Trace name must not be blank'],
    ['a non-string name', { name: 1 }, 'Trace name must not be blank'],
    ['an unknown status', { name: 'n', status: 'fine' }, 'Trace status is invalid'],
    ['a blank status message', { name: 'n', statusMessage: ' ' }, 'Trace status message must not be blank'],
    ['a non-string status message', { name: 'n', statusMessage: 3 }, 'Trace status message must not be blank'],
    ['array attributes', { name: 'n', attributes: [] }, 'Trace attributes must be a primitive record'],
    ['null attributes', { name: 'n', attributes: null }, 'Trace attributes must be a primitive record'],
    ['class-instance attributes', { name: 'n', attributes: new Map() }, 'Trace attributes must be a primitive record'],
    [
      'a blank attribute name',
      { name: 'n', attributes: { ' ': 1 } },
      'Trace attribute names must be non-blank and NUL-free',
    ],
    [
      'a NUL attribute name',
      { name: 'n', attributes: { 'a\0b': 1 } },
      'Trace attribute names must be non-blank and NUL-free',
    ],
    [
      'an object attribute value',
      { name: 'n', attributes: { a: {} } },
      'Trace attribute values must be finite primitives',
    ],
    [
      'an infinite attribute value',
      { name: 'n', attributes: { a: Infinity } },
      'Trace attribute values must be finite primitives',
    ],
    ['non-array events', { name: 'n', events: {} }, 'Trace events must be an array'],
    ['a non-object event', { name: 'n', events: [1] }, 'Trace events must be objects'],
    ['a blank event name', { name: 'n', events: [{ name: '' }] }, 'Trace event names must not be blank'],
    [
      'bad event attributes',
      { name: 'n', events: [{ name: 'e', attributes: { a: null } }] },
      'Trace attribute values must be finite primitives',
    ],
  ])('should reject %s', (_label, record, message) => {
    // Arrange
    const candidate: unknown = record;

    // Act
    const actual = validator.record(candidate);

    // Assert
    actual.ok.should.be.false();
    if (actual.ok) return;
    actual.error.should.match({ code: 'invalid-input', operation: 'emit', message });
  });

  it('should name the injected operation on a rejection', () => {
    // Arrange
    const flushing = new TraceRecordValidator('record');

    // Act
    const actual = flushing.attributes([]);

    // Assert
    actual.ok.should.be.false();
    if (actual.ok) return;
    actual.error.operation.should.eql('record');
  });

  it('should accept null-prototype attributes', () => {
    // Arrange
    const attributes = Object.assign(Object.create(null), { a: 1 });

    // Act
    const actual = validator.attributes(attributes);

    // Assert
    actual.should.eql({ ok: true, value: { a: 1 } });
  });
});
