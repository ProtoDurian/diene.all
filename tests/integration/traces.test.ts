import { describe, it } from 'bun:test';
import { SpanStatusCode, trace } from '@opentelemetry/api';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
  AlwaysOffSampler,
  BatchSpanProcessor,
  ConsoleSpanExporter,
  InMemorySpanExporter,
} from '@opentelemetry/sdk-trace-base';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import 'should';
import { SdkTraceEmitter, SdkTraceSignalFactories, TraceSignalFactory } from '../../src/adapters/signals/traces';
import { RecordingTraceFactories, scriptedTracer } from './support/doubles';
import { expectErr, expectOk } from './support/result';

const resource = resourceFromAttributes({ 'service.name': 'svc' });
const scope = { name: 'svc', version: '1.0.0' };
const settings = { sampler: undefined, otlp: { url: 'http://127.0.0.1:4318/v1/traces' } };

function liveSignal(failures: { flush?: boolean; shutdown?: boolean } = {}) {
  const factories = new RecordingTraceFactories(failures);
  const signal = new TraceSignalFactory(factories).create({
    selection: { console: false, otlp: true },
    resource,
    scope,
    settings,
  });
  return { factories, signal };
}

describe('SdkTraceSignalFactories', () => {
  it('should build the SDK exporters, a batch processor and a registered node provider', async () => {
    // Arrange
    const factories = new SdkTraceSignalFactories();

    // Act
    const consoleExporter = factories.console();
    const otlpExporter = factories.otlp(settings.otlp);
    const processor = factories.processor(new InMemorySpanExporter());
    const provider = factories.provider({ resource, sampler: new AlwaysOffSampler(), spanProcessors: [processor] });

    // Assert
    (consoleExporter instanceof ConsoleSpanExporter).should.be.true();
    (otlpExporter instanceof OTLPTraceExporter).should.be.true();
    (processor instanceof BatchSpanProcessor).should.be.true();
    (provider instanceof NodeTracerProvider).should.be.true();
    (trace.getTracerProvider() !== undefined).should.be.true();
    await Promise.all([consoleExporter.shutdown(), otlpExporter.shutdown(), provider.shutdown()]);
    trace.disable();
  });

  it('should leave the sampler to the SDK when none is given', async () => {
    // Arrange
    const factories = new SdkTraceSignalFactories();

    // Act
    const provider = factories.provider({ resource, spanProcessors: [] });

    // Assert
    (provider instanceof NodeTracerProvider).should.be.true();
    await provider.shutdown();
    trace.disable();
  });
});

describe('TraceSignalFactory', () => {
  it('should stay inactive with a no-op tracer when nothing is selected', async () => {
    // Arrange
    const factories = new RecordingTraceFactories();

    // Act
    const signal = new TraceSignalFactory(factories).create({
      selection: { console: false, otlp: false },
      resource,
      scope,
      settings,
    });

    // Assert
    signal.active.should.be.false();
    factories.calls.should.eql([]);
    signal.tracer.startSpan('x').isRecording().should.be.false();
    await expectOk(signal.emitter.emit({ name: 'dropped' }));
  });

  it('should build one processor per exporter and hand the sampler to the provider', () => {
    // Arrange
    const factories = new RecordingTraceFactories();
    const sampler = new AlwaysOffSampler();

    // Act
    const signal = new TraceSignalFactory(factories).create({
      selection: { console: true, otlp: true },
      resource,
      scope,
      settings: { ...settings, sampler },
    });

    // Assert
    signal.active.should.be.true();
    factories.calls.should.eql(['console', 'processor', 'otlp', 'processor']);
    factories.providers[0]?.sampler?.should.equal(sampler);
    factories.providers[0]?.spanProcessors.length.should.eql(2);
  });

  it('should default to the SDK factories', async () => {
    // Arrange
    const factory = new TraceSignalFactory();

    // Act
    const signal = factory.create({ selection: { console: true, otlp: false }, resource, scope, settings });

    // Assert
    signal.active.should.be.true();
    await signal.provider?.shutdown();
    trace.disable();
  });
});

describe('SdkTraceEmitter', () => {
  it('should emit a span with attributes, events and status onto the resource', async () => {
    // Arrange
    const { factories, signal } = liveSignal();

    // Act
    await expectOk(
      signal.emitter.emit({
        name: 'checkout',
        attributes: { order: 7 },
        events: [{ name: 'paid', attributes: { amount: 3 } }],
        status: 'error',
        statusMessage: 'declined',
      }),
    );
    await expectOk(signal.emitter.emit({ name: 'plain', statusMessage: 'only a message' }));
    await expectOk(signal.emitter.emit({ name: 'fine', status: 'ok' }));
    await expectOk(signal.emitter.flush());

    // Assert
    const spans = factories.exporter.getFinishedSpans();
    spans.map(span => span.name).should.eql(['checkout', 'plain', 'fine']);
    spans[0]?.attributes.should.eql({ order: 7 });
    spans[0]?.events.map(event => event.name).should.eql(['paid']);
    spans[0]?.status.should.eql({ code: SpanStatusCode.ERROR, message: 'declined' });
    spans[1]?.status.should.eql({ code: SpanStatusCode.UNSET });
    spans[2]?.status.should.eql({ code: SpanStatusCode.OK });
    spans[0]?.resource.attributes.should.eql({ 'service.name': 'svc' });
    spans[0]?.instrumentationScope.should.match(scope);
  });

  it('should reject an invalid record before touching the tracer', async () => {
    // Arrange
    const { tracer, ends } = scriptedTracer({}, true);
    const emitter = new SdkTraceEmitter(tracer, liveSignal().signal.provider);

    // Act
    const actual = await expectErr(emitter.emit({ name: '' }));

    // Assert
    actual.code.should.eql('invalid-input');
    ends().should.eql(0);
  });

  it.each([
    ['startSpan throws an Error', scriptedTracer({}, true), 'startSpan failed', 0],
    [
      'addEvent throws a non-Error',
      scriptedTracer({
        addEvent: () => {
          throw 'event';
        },
      }),
      'event',
      1,
    ],
    [
      'end throws, and the retry end also throws',
      scriptedTracer({
        end: () => {
          throw new Error('end failed');
        },
      }),
      'end failed',
      2,
    ],
  ])('should return an io error when %s and end the span at most twice', async (_label, scripted, cause, ends) => {
    // Arrange
    const emitter = new SdkTraceEmitter(scripted.tracer, liveSignal().signal.provider);

    // Act
    const actual = await expectErr(emitter.emit({ name: 'n', events: [{ name: 'e' }] }));

    // Assert
    actual.should.match({ code: 'io', operation: 'emit', details: { cause } });
    scripted.ends().should.eql(ends);
  });

  it('should turn a failed provider flush into an io error', async () => {
    // Arrange
    const { signal } = liveSignal({ flush: true });

    // Act
    const actual = await expectErr(signal.emitter.flush());

    // Assert
    actual.should.match({ code: 'io', operation: 'flush', details: { cause: 'trace flush failed' } });
  });
});
