import { describe, it } from 'bun:test';
import 'should';
import { TraceError } from '../../src/lib/trace-seam';
import { InMemoryTraceEmitter } from '../../src/test-helper';

describe('InMemoryTraceEmitter', () => {
  it('should record emits and flushes in sequence as frozen copies', async () => {
    // Arrange
    const emitter = new InMemoryTraceEmitter();
    const record = {
      name: 'work',
      attributes: { a: 1 },
      events: [{ name: 'e', attributes: { b: true } }, { name: 'f' }],
      status: 'error' as const,
      statusMessage: 'bad',
    };

    // Act
    await emitter.emit(record).unwrap();
    await emitter.flush().unwrap();

    // Assert
    emitter.records.should.eql([record]);
    emitter.calls.should.eql([
      { method: 'emit', record, sequence: 0 },
      { method: 'flush', sequence: 1 },
    ]);
    Object.isFrozen(emitter.records[0]?.events?.[0]?.attributes).should.be.true();
    const [first, second] = [emitter.records[0], emitter.records[0]];
    (first !== second).should.be.true();
  });

  it('should reject an invalid record without recording it', async () => {
    // Arrange
    const emitter = new InMemoryTraceEmitter();

    // Act
    const error = await emitter.emit({ name: ' ' }).unwrapErr();

    // Assert
    error.code.should.eql('invalid-input');
    emitter.calls.should.eql([]);
  });

  it('should fail the next call once, recording the attempt but not the record', async () => {
    // Arrange
    const emitter = new InMemoryTraceEmitter();
    const failure = new TraceError('unavailable', 'emit', 'down');
    emitter.failNext(failure);

    // Act
    const first = await emitter.emit({ name: 'lost' }).unwrapErr();
    await emitter.emit({ name: 'kept' }).unwrap();
    emitter.failNext(failure);
    const flushed = await emitter.flush().unwrapErr();

    // Assert
    first.should.equal(failure);
    flushed.should.equal(failure);
    emitter.records.should.eql([{ name: 'kept' }]);
    emitter.calls.map(call => call.method).should.eql(['emit', 'emit', 'flush']);
  });
});
