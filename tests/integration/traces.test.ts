import { afterEach, describe, it } from 'bun:test';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { context, propagation, SpanStatusCode, trace } from '@opentelemetry/api';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
  AlwaysOffSampler,
  AlwaysOnSampler,
  BasicTracerProvider,
  BatchSpanProcessor,
  ConsoleSpanExporter,
  InMemorySpanExporter,
  SimpleSpanProcessor,
} from '@opentelemetry/sdk-trace-base';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import 'should';
import {
  GlobalTraceRegistrar,
  SdkTraceEmitter,
  SdkTraceSignalFactories,
  TraceSignalFactory,
} from '../../src/adapters/signals/traces';
import {
  exporterSettings,
  RecordingTraceFactories,
  StackContextManager,
  scriptedTracer,
  withProcessEnv,
} from './support/doubles';
import { expectErr, expectOk } from './support/result';

const resource = resourceFromAttributes({ 'service.name': 'svc' });
const scope = { name: 'svc', version: '1.0.0' };
const otlp = {
  url: 'http://127.0.0.1:54321/custom',
  headers: { tenant: 'review' },
  timeoutMillis: 1234,
  compression: 'none' as const,
  tls: {},
};
const agent = { keepAlive: true };
const limits = {
  general: { attributeCountLimit: 128, attributeValueLengthLimit: Number.POSITIVE_INFINITY },
  span: {
    attributeCountLimit: 128,
    attributeValueLengthLimit: Number.POSITIVE_INFINITY,
    attributePerEventCountLimit: 128,
    attributePerLinkCountLimit: 128,
    eventCountLimit: 128,
    linkCountLimit: 128,
  },
};
const batch = { exportTimeoutMillis: 1000, maxExportBatchSize: 8, maxQueueSize: 16, scheduledDelayMillis: 10 };
const settings = { sampler: new AlwaysOnSampler(), batch, limits, otlp };

const link = { context: { traceId: 'ab'.repeat(16), spanId: 'cd'.repeat(8), traceFlags: 1 } };

async function limitedSpan(spanLimits: typeof limits, ambient: Record<string, string> = {}) {
  const exporter = new InMemorySpanExporter();
  return withProcessEnv(ambient, async () => {
    const provider = new SdkTraceSignalFactories().provider({
      limits: spanLimits,
      resource,
      sampler: new AlwaysOnSampler(),
      spanProcessors: [new SimpleSpanProcessor(exporter)],
    });
    const span = provider.getTracer('svc').startSpan('limited', {
      attributes: { first: 'long', second: 'value' },
      links: [{ ...link, attributes: { kind: 'peer' } }],
    });
    span.addEvent('paid', { amount: 3 });
    span.end();
    const [finished] = exporter.getFinishedSpans();
    await provider.shutdown();
    return finished;
  });
}

function liveSignal(failures: { flush?: boolean; shutdown?: boolean } = {}) {
  const factories = new RecordingTraceFactories(failures);
  const signal = new TraceSignalFactory(factories).create({
    agent,
    selection: { console: false, otlp: true },
    resource,
    scope,
    settings,
  });
  return { factories, signal };
}

function globalTracerRecords(): boolean {
  const span = trace.getTracer('auto-instrumentation').startSpan('probe');
  const recording = span.isRecording();
  span.end();
  return recording;
}

afterEach(() => {
  trace.disable();
  context.disable();
  propagation.disable();
});

describe('SdkTraceSignalFactories', () => {
  it('should build the SDK exporters, a configured batch processor and an unregistered node provider', async () => {
    // Arrange
    const factories = new SdkTraceSignalFactories();

    // Act
    const consoleExporter = factories.console();
    const otlpExporter = factories.otlp(otlp, agent);
    const processor = factories.processor(new InMemorySpanExporter(), batch);
    const provider = factories.provider({
      limits,
      resource,
      sampler: new AlwaysOffSampler(),
      spanProcessors: [processor],
    });

    // Assert
    (consoleExporter instanceof ConsoleSpanExporter).should.be.true();
    (otlpExporter instanceof OTLPTraceExporter).should.be.true();
    (processor instanceof BatchSpanProcessor).should.be.true();
    (processor as unknown as { _maxQueueSize: number })._maxQueueSize.should.eql(16);
    (provider instanceof NodeTracerProvider).should.be.true();
    globalTracerRecords().should.be.false();
    await Promise.all([consoleExporter.shutdown(), otlpExporter.shutdown(), provider.shutdown()]);
  });

  it('should configure the real OTLP exporter from the options, not from conflicting process variables', async () => {
    // Arrange
    const factories = new SdkTraceSignalFactories();

    // Act
    const actual = await withProcessEnv(
      {
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'http://process:4318/v1/traces',
        OTEL_EXPORTER_OTLP_TRACES_TIMEOUT: '9999',
        OTEL_EXPORTER_OTLP_TRACES_HEADERS: 'tenant=process',
        OTEL_EXPORTER_OTLP_TRACES_COMPRESSION: 'gzip',
      },
      async () => {
        const exporter = factories.otlp(otlp, agent);
        const read = await exporterSettings(exporter);
        await exporter.shutdown();
        return read;
      },
    );

    // Assert
    actual.should.match({ url: otlp.url, timeoutMillis: 1234, compression: 'none', headers: { tenant: 'review' } });
  });

  it('should hand the agent options to the real exporter, not the process certificate variables', async () => {
    // Arrange
    const factories = new SdkTraceSignalFactories();
    const directory = mkdtempSync(join(tmpdir(), 'otel-tls-'));
    writeFileSync(join(directory, 'process.pem'), 'process');
    const ca = Buffer.from('injected');

    // Act
    const actual = await withProcessEnv(
      {
        OTEL_EXPORTER_OTLP_TRACES_CERTIFICATE: join(directory, 'process.pem'),
        OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE: join(directory, 'process.pem'),
        OTEL_EXPORTER_OTLP_CLIENT_KEY: join(directory, 'process.pem'),
      },
      async () => {
        const exporter = factories.otlp(otlp, { keepAlive: true, ca });
        const read = await exporterSettings(exporter);
        await exporter.shutdown();
        return { ...read.agent };
      },
    );

    // Assert
    actual.should.match({ keepAlive: true, ca });
    [actual.cert, actual.key].should.eql([undefined, undefined]);
  });

  it('should keep spans whole under the default limits even when the process limits are tight', async () => {
    // Arrange
    const ambient = {
      OTEL_ATTRIBUTE_COUNT_LIMIT: '1',
      OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT: '1',
      OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT: '1',
      OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT: '1',
      OTEL_SPAN_ATTRIBUTE_PER_EVENT_COUNT_LIMIT: '0',
      OTEL_SPAN_ATTRIBUTE_PER_LINK_COUNT_LIMIT: '0',
      OTEL_SPAN_EVENT_COUNT_LIMIT: '0',
      OTEL_SPAN_LINK_COUNT_LIMIT: '0',
    };

    // Act
    const actual = await limitedSpan(limits, ambient);

    // Assert
    actual?.attributes.should.eql({ first: 'long', second: 'value' });
    actual?.events.map(event => event.attributes).should.eql([{ amount: 3 }]);
    actual?.links.map(item => item.attributes).should.eql([{ kind: 'peer' }]);
    [actual?.droppedAttributesCount, actual?.droppedEventsCount, actual?.droppedLinksCount].should.eql([0, 0, 0]);
  });

  it('should enforce the injected span limits', async () => {
    // Arrange
    const tight = {
      general: { attributeCountLimit: 1, attributeValueLengthLimit: 2 },
      span: {
        attributeCountLimit: 1,
        attributeValueLengthLimit: 2,
        attributePerEventCountLimit: 0,
        attributePerLinkCountLimit: 0,
        eventCountLimit: 1,
        linkCountLimit: 1,
      },
    };

    // Act
    const actual = await limitedSpan(tight);

    // Assert
    actual?.attributes.should.eql({ first: 'lo' });
    actual?.droppedAttributesCount.should.eql(1);
    actual?.events.map(event => event.attributes).should.eql([{}]);
    actual?.links.map(item => item.attributes ?? {}).should.eql([{}]);
  });

  it('should sample with the given sampler even when OTEL_TRACES_SAMPLER says otherwise', async () => {
    // Arrange
    const factories = new SdkTraceSignalFactories();

    // Act
    const recording = await withProcessEnv({ OTEL_TRACES_SAMPLER: 'always_on' }, async () => {
      const provider = factories.provider({ limits, resource, sampler: new AlwaysOffSampler(), spanProcessors: [] });
      const span = provider.getTracer('svc').startSpan('x');
      const recording = span.isRecording();
      span.end();
      await provider.shutdown();
      return recording;
    });

    // Assert
    recording.should.be.false();
  });
});

describe('GlobalTraceRegistrar', () => {
  it('should claim the free tracer, context and propagator slots and release exactly those', async () => {
    // Arrange
    const exporter = new InMemorySpanExporter();
    const provider = new BasicTracerProvider({ resource, spanProcessors: [new SimpleSpanProcessor(exporter)] });

    // Act
    const registration = new GlobalTraceRegistrar().claim(provider);
    const parent = trace.setSpanContext(context.active(), {
      traceId: 'ab'.repeat(16),
      spanId: 'cd'.repeat(8),
      traceFlags: 1,
    });
    const carried = context.with(parent, () => trace.getSpanContext(context.active())?.traceId);
    const headers: Record<string, string> = {};
    propagation.inject(parent, headers);
    globalTracerRecords().should.be.true();
    registration.release();

    // Assert
    [registration.tracer, registration.contextManager, registration.propagator].should.eql([true, true, true]);
    (carried ?? '').should.eql('ab'.repeat(16));
    (headers.traceparent ?? '').should.startWith('00-abab');
    exporter
      .getFinishedSpans()
      .map(span => span.name)
      .should.eql(['probe']);
    globalTracerRecords().should.be.false();
    await provider.shutdown();
  });

  it('should leave a host provider and its context manager untouched', async () => {
    // Arrange
    const host = new InMemorySpanExporter();
    const hostProvider = new BasicTracerProvider({ resource, spanProcessors: [new SimpleSpanProcessor(host)] });
    trace.setGlobalTracerProvider(hostProvider);
    const ours = new BasicTracerProvider({ resource });

    // Act
    const registration = new GlobalTraceRegistrar().claim(ours);
    registration.release();
    globalTracerRecords();

    // Assert
    [registration.tracer, registration.contextManager, registration.propagator].should.eql([false, false, false]);
    host
      .getFinishedSpans()
      .map(span => span.name)
      .should.eql(['probe']);
    await Promise.all([hostProvider.shutdown(), ours.shutdown()]);
  });

  it('should own the tracer but not a context manager someone else set', () => {
    // Arrange
    const manager = new StackContextManager();
    context.setGlobalContextManager(manager);

    // Act
    const registration = new GlobalTraceRegistrar().claim(new BasicTracerProvider({ resource }));
    registration.release();

    // Assert
    [registration.tracer, registration.contextManager].should.eql([true, false]);
    context.setGlobalContextManager(new StackContextManager()).should.be.false();
  });
});

describe('TraceSignalFactory', () => {
  it('should stay inactive with a no-op tracer when nothing is selected', async () => {
    // Arrange
    const factories = new RecordingTraceFactories();

    // Act
    const signal = new TraceSignalFactory(factories).create({
      agent,
      selection: { console: false, otlp: false },
      resource,
      scope,
      settings,
    });

    // Assert
    signal.active.should.be.false();
    signal.registration.tracer.should.be.false();
    factories.calls.should.eql([]);
    signal.tracer.startSpan('x').isRecording().should.be.false();
    await expectOk(signal.emitter.emit({ name: 'dropped' }));
  });

  it('should build one configured processor per exporter, hand over the sampler and claim the globals', () => {
    // Arrange
    const factories = new RecordingTraceFactories();
    const sampler = new AlwaysOffSampler();

    // Act
    const signal = new TraceSignalFactory(factories).create({
      agent,
      selection: { console: true, otlp: true },
      resource,
      scope,
      settings: { ...settings, sampler },
    });

    // Assert
    signal.active.should.be.true();
    signal.registration.tracer.should.be.true();
    factories.calls.should.eql(['console', 'processor', 'otlp', 'processor']);
    factories.batches.should.eql([batch, batch]);
    factories.agents.should.eql([agent]);
    factories.providers[0]?.limits.should.equal(limits);
    factories.providers[0]?.sampler.should.equal(sampler);
    factories.providers[0]?.spanProcessors.length.should.eql(2);
    signal.registration.release();
  });

  it('should default to the SDK factories', async () => {
    // Arrange
    const factory = new TraceSignalFactory();

    // Act
    const signal = factory.create({ agent, selection: { console: true, otlp: false }, resource, scope, settings });

    // Assert
    signal.active.should.be.true();
    await signal.provider?.shutdown();
    signal.registration.release();
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
