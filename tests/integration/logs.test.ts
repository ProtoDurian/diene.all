import { describe, it } from 'bun:test';
import { InMemoryLoggerSink } from '@atomicloud/diene.interfaces/test-helper';
import { context, type SpanContext, trace } from '@opentelemetry/api';
import 'should';
import {
  LoggerSignalFactory,
  OTLP_LOGS_BRIDGE_STATUS,
  PinoLoggerSink,
  TraceContextFields,
} from '../../src/adapters/signals/logs';
import { CaptureStream, StackContextManager, throwingLogger } from './support/doubles';
import { expectErr, expectOk } from './support/result';

const SPAN: SpanContext = { traceId: '0af7651916cd43dd8448eb211c80319c', spanId: 'b7ad6b7169203331', traceFlags: 1 };
const resource = { 'service.name': 'svc', 'atomi.landscape': 'lapras' };

describe('TraceContextFields', () => {
  it('should expose the active span ids in snake case', () => {
    // Arrange
    const fields = new TraceContextFields(() => SPAN);

    // Act
    const actual = fields.fields();

    // Assert
    actual.should.eql({ span_id: SPAN.spanId, trace_flags: 1, trace_id: SPAN.traceId });
  });

  it.each([
    ['no active span', undefined],
    ['an invalid span context', { traceId: '0'.repeat(32), spanId: '0'.repeat(16), traceFlags: 0 }],
  ])('should add nothing for %s', (_label, spanContext) => {
    // Arrange
    const fields = new TraceContextFields(() => spanContext);

    // Act
    const actual = fields.fields();

    // Assert
    actual.should.eql({});
  });

  it('should read the span from the OpenTelemetry context by default', () => {
    // Arrange
    const fields = new TraceContextFields();
    context.setGlobalContextManager(new StackContextManager());
    const active = trace.setSpanContext(context.active(), SPAN);

    // Act
    const inside = context.with(active, () => fields.fields());
    const outside = fields.fields();
    context.disable();

    // Assert
    inside.should.eql({ span_id: SPAN.spanId, trace_flags: 1, trace_id: SPAN.traceId });
    outside.should.eql({});
  });
});

describe('LoggerSignalFactory', () => {
  it('should write pino JSON with the resource and the trace context', async () => {
    // Arrange
    const stream = new CaptureStream();
    const signal = new LoggerSignalFactory(new TraceContextFields(() => SPAN)).create(true, resource, stream);

    // Act
    await expectOk(signal.sink.emit({ level: 'warn', message: 'hello', attributes: { order: 7 } }));
    await expectOk(signal.sink.flush());

    // Assert
    signal.active.should.be.true();
    signal.otlpBridge.should.eql(OTLP_LOGS_BRIDGE_STATUS);
    stream.lines.length.should.eql(1);
    stream.lines[0]?.should.match({ ...resource, level: 40, msg: 'hello', order: 7, trace_id: SPAN.traceId });
  });

  it('should write nothing when inactive', async () => {
    // Arrange
    const stream = new CaptureStream();
    const signal = new LoggerSignalFactory().create(false, resource, stream);

    // Act
    await expectOk(signal.sink.emit({ level: 'info', message: 'quiet' }));

    // Assert
    signal.active.should.be.false();
    stream.lines.should.eql([]);
  });

  it('should default the destination to stdout', () => {
    // Arrange
    const factory = new LoggerSignalFactory();

    // Act
    const signal = factory.create(false, resource);

    // Assert
    signal.logger.isLevelEnabled('trace').should.be.false();
  });
});

describe('PinoLoggerSink', () => {
  it('should reject an invalid record the same way the shared mock does', async () => {
    // Arrange
    const sink = new PinoLoggerSink(throwingLogger());
    const mock = new InMemoryLoggerSink();
    const record = { level: 'loud', message: 'x' } as never;

    // Act
    const actual = await expectErr(sink.emit(record));
    const expected = await expectErr(mock.emit(record));

    // Assert
    actual.should.match({ port: 'logging', code: expected.code, message: expected.message });
  });

  it.each([
    ['an Error', new Error('pino failed'), 'pino failed'],
    ['a non-Error', 'boom', 'boom'],
  ])('should turn %s thrown by pino into an io error', async (_label, thrown, cause) => {
    // Arrange
    const fail = () => {
      throw thrown;
    };
    const sink = new PinoLoggerSink({ info: fail, flush: fail } as never);

    // Act
    const emitted = await expectErr(sink.emit({ level: 'info', message: 'x' }));
    const flushed = await expectErr(sink.flush());

    // Assert
    emitted.should.match({ code: 'io', operation: 'emit', details: { cause } });
    flushed.should.match({ code: 'io', operation: 'flush', details: { cause } });
  });
});
