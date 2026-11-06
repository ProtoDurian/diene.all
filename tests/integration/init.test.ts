import { describe, it } from 'bun:test';
import { mkdtempSync, writeFileSync } from 'node:fs';
import type { AgentOptions } from 'node:https';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { type MetricsCollector, type MetricsError, portError } from '@atomicloud/diene.interfaces';
import {
  assertLogRecords,
  assertMetricRecords,
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
} from '@atomicloud/diene.interfaces/test-helper';
import { Ok, Res } from '@atomicloud/diene.result';
import { context, propagation, trace } from '@opentelemetry/api';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { BasicTracerProvider, InMemorySpanExporter, SimpleSpanProcessor } from '@opentelemetry/sdk-trace-base';
import 'should';
import { OtelBootstrap, type OtelRuntime, TelemetryLifecycleError } from '../../src/adapters/init';
import { LoggerSignalFactory } from '../../src/adapters/signals/logs';
import { MetricSignalFactory, SdkMetricExporterFactories } from '../../src/adapters/signals/metrics';
import { OtlpTlsFileError } from '../../src/adapters/signals/tls';
import { SdkTraceSignalFactories, TraceSignalFactory } from '../../src/adapters/signals/traces';
import type { OtlpExporterOptions } from '../../src/lib/endpoint';
import type { AppIdentity } from '../../src/lib/resource';
import { defaultOtelBlock, type OtelBlock } from '../../src/lib/schema';
import { TraceError } from '../../src/lib/trace-seam';
import { InMemoryTraceEmitter } from '../../src/test-helper/helper';
import {
  CaptureStream,
  exporterSettings,
  RecordingMetricExporters,
  RecordingTraceFactories,
  withProcessEnv,
} from './support/doubles';
import { expectOk } from './support/result';

const identity: AppIdentity = {
  landscape: 'lapras',
  platform: 'atomi',
  service: 'svc',
  module: 'api',
  version: '2.0.0',
};
const semantic = {
  'deployment.environment.name': 'lapras',
  'service.namespace': 'atomi',
  'service.name': 'svc',
  'service.version': '2.0.0',
  'atomi.landscape': 'lapras',
  'atomi.module': 'api',
  'atomi.platform': 'atomi',
  'atomi.service': 'svc',
  'atomi.version': '2.0.0',
};
const on = {
  console: { enabled: true },
  otlp: { ...defaultOtelBlock.logs.exporter.otlp, enabled: true, endpoint: 'http://127.0.0.1:4318' },
};
const liveBlock: OtelBlock = {
  logs: { enabled: true, exporter: on },
  metrics: { ...defaultOtelBlock.metrics, exporter: on },
  traces: { ...defaultOtelBlock.traces, exporter: on },
};

function recordingBootstrap(failures: { flush?: boolean; shutdown?: boolean } = {}, log: string[] = []) {
  const metricExporters = new RecordingMetricExporters();
  const traceFactories = new RecordingTraceFactories(failures, log);
  const bootstrap = new OtelBootstrap({
    logs: new LoggerSignalFactory(),
    metrics: new MetricSignalFactory(metricExporters),
    traces: new TraceSignalFactory(traceFactories),
  });
  return { bootstrap, metricExporters, traceFactories };
}

function globalTracerRecords(): boolean {
  const span = trace.getTracer('auto-instrumentation').startSpan('auto');
  const recording = span.isRecording();
  span.end();
  return recording;
}

async function lifecycleFailure(run: () => Promise<void>): Promise<readonly TelemetryLifecycleError[]> {
  const failure = await run().then(
    () => undefined,
    (error: unknown) => error,
  );
  (failure instanceof AggregateError).should.be.true();
  const errors = (failure as AggregateError).errors as TelemetryLifecycleError[];
  errors.every(error => error instanceof TelemetryLifecycleError).should.be.true();
  return errors;
}

class CapturingSdkTraceFactories extends SdkTraceSignalFactories {
  readonly exporters: unknown[] = [];

  override otlp(options: OtlpExporterOptions, agent: AgentOptions) {
    const exporter = super.otlp(options, agent);
    this.exporters.push(exporter);
    return exporter;
  }
}

class CapturingSdkMetricExporters extends SdkMetricExporterFactories {
  readonly exporters: unknown[] = [];

  override otlp(options: OtlpExporterOptions, temporality: 'cumulative' | 'delta' | 'lowmemory', agent: AgentOptions) {
    const exporter = super.otlp(options, temporality, agent);
    this.exporters.push(exporter);
    return exporter;
  }
}

describe('OtelBootstrap off by default', () => {
  it('should build no provider, claim no global and stay inactive for the canonical block', async () => {
    // Arrange
    const { bootstrap, metricExporters, traceFactories } = recordingBootstrap();

    // Act
    const runtime = bootstrap.init(defaultOtelBlock, identity, { environment: {} });
    await runtime.flush();
    await runtime.shutdown();

    // Assert
    runtime.active.should.eql({ logs: false, metrics: false, traces: false });
    runtime.globalRegistered.should.be.false();
    metricExporters.calls.should.eql([]);
    traceFactories.calls.should.eql([]);
    runtime.otlpLogsBridge.should.eql('stubbed');
    runtime.resourceAttributes.should.eql(semantic);
  });

  it('should read process.env when no environment is given', () => {
    // Arrange
    const bootstrap = new OtelBootstrap();

    // Act
    const runtime = bootstrap.init(defaultOtelBlock, identity);

    // Assert
    runtime.block.should.eql(defaultOtelBlock);
    runtime.identity.should.eql(identity);
  });

  it('should build nothing when OTEL_SDK_DISABLED is true, even with seams', async () => {
    // Arrange
    const { bootstrap, metricExporters, traceFactories } = recordingBootstrap();
    const logger = new InMemoryLoggerSink();

    // Act
    const runtime = bootstrap.init(liveBlock, identity, {
      environment: { OTEL_SDK_DISABLED: 'true' },
      seams: { logger },
    });
    await expectOk(runtime.loggerSink.emit({ level: 'info', message: 'dropped' }));

    // Assert
    runtime.active.should.eql({ logs: false, metrics: false, traces: false });
    metricExporters.calls.should.eql([]);
    traceFactories.calls.should.eql([]);
    logger.records.should.eql([]);
  });
});

describe('OtelBootstrap with the shared interfaces mocks', () => {
  it('should route every signal into the injected seams and build no SDK pipeline', async () => {
    // Arrange
    const { bootstrap, metricExporters, traceFactories } = recordingBootstrap();
    const logger = new InMemoryLoggerSink();
    const metrics = new InMemoryMetricsCollector();
    const traces = new InMemoryTraceEmitter();
    const runtime = bootstrap.init(liveBlock, identity, { environment: {}, seams: { logger, metrics, traces } });

    // Act
    await expectOk(runtime.loggerSink.emit({ level: 'info', message: 'hi', attributes: { a: 1 } }));
    await expectOk(runtime.metricsCollector.record({ kind: 'counter', name: 'jobs', value: 1 }));
    await expectOk(runtime.traceEmitter.emit({ name: 'work' }));
    await runtime.shutdown();

    // Assert
    assertLogRecords(logger, [{ level: 'info', message: 'hi', attributes: { a: 1 } }]);
    assertMetricRecords(metrics, [{ kind: 'counter', name: 'jobs', value: 1 }]);
    traces.records.should.eql([{ name: 'work' }]);
    runtime.active.should.eql({ logs: false, metrics: false, traces: false });
    runtime.globalRegistered.should.be.false();
    metricExporters.calls.should.eql([]);
    traceFactories.calls.should.eql([]);
    runtime.resourceAttributes.should.eql(semantic);
  });
});

describe('OtelBootstrap lifecycle failures', () => {
  it('should report every seam that fails to flush, labelled by signal and phase', async () => {
    // Arrange
    const logger = new InMemoryLoggerSink();
    const metrics = new InMemoryMetricsCollector();
    const traces = new InMemoryTraceEmitter();
    const runtime = new OtelBootstrap().init(liveBlock, identity, {
      environment: {},
      seams: { logger, metrics, traces },
    });
    logger.failNext(portError('logging', 'io', 'flush', 'log flush failed'));
    metrics.failNext(portError('metrics', 'io', 'flush', 'metric flush failed'));
    traces.failNext(new TraceError('io', 'flush', 'trace flush failed'));

    // Act
    const errors = await lifecycleFailure(() => runtime.shutdown());

    // Assert
    errors
      .map(error => [error.signal, error.phase, error.message])
      .should.eql([
        ['logs', 'flush', 'logs flush failed: log flush failed'],
        ['metrics', 'flush', 'metrics flush failed: metric flush failed'],
        ['traces', 'flush', 'traces flush failed: trace flush failed'],
      ]);
    (errors[1]?.cause as Error).message.should.eql('metric flush failed');
  });

  it('should wait for a slow flush before shutting providers down, even after an early rejection', async () => {
    // Arrange
    const log: string[] = [];
    const { bootstrap } = recordingBootstrap({}, log);
    const logger = new InMemoryLoggerSink();
    logger.failNext(portError('logging', 'io', 'flush', 'early'));
    const slow: MetricsCollector = {
      record: () => Ok(undefined),
      flush: () =>
        Res.fromSerial<void, MetricsError>(
          new Promise<['ok', undefined]>(resolve =>
            setTimeout(() => {
              log.push('metrics flushed');
              resolve(['ok', undefined]);
            }, 30),
          ),
        ),
    };
    const runtime = bootstrap.init(liveBlock, identity, { environment: {}, seams: { logger, metrics: slow } });

    // Act
    const errors = await lifecycleFailure(() => runtime.shutdown());

    // Assert
    log.should.eql(['metrics flushed', 'traces shutdown']);
    errors.map(error => `${error.signal} ${error.phase}`).should.eql(['logs flush']);
  });

  it('should collect flush and provider shutdown failures together', async () => {
    // Arrange
    const { bootstrap } = recordingBootstrap({ flush: true, shutdown: true });
    const metrics = new InMemoryMetricsCollector();
    metrics.failNext(portError('metrics', 'io', 'flush', 'metric flush failed'));
    const runtime = bootstrap.init(liveBlock, identity, { environment: {}, seams: { metrics } });

    // Act
    const errors = await lifecycleFailure(() => runtime.shutdown());

    // Assert
    errors
      .map(error => `${error.signal} ${error.phase}`)
      .should.eql(['metrics flush', 'traces flush', 'traces shutdown']);
    globalTracerRecords().should.be.false();
  });

  it('should throw an AggregateError from flush too', async () => {
    // Arrange
    const traces = new InMemoryTraceEmitter();
    const runtime = new OtelBootstrap().init(defaultOtelBlock, identity, { environment: {}, seams: { traces } });
    traces.failNext(new TraceError('io', 'flush', 'down'));

    // Act
    const errors = await lifecycleFailure(() => runtime.flush());

    // Assert
    errors.map(error => `${error.signal} ${error.phase}`).should.eql(['traces flush']);
  });
});

describe('OtelBootstrap with SDK pipelines', () => {
  it('should export metrics and spans on the mapped resource and log with the resource', async () => {
    // Arrange
    const { bootstrap, metricExporters, traceFactories } = recordingBootstrap();
    const stream = new CaptureStream();
    const runtime = bootstrap.init(liveBlock, identity, { environment: {}, destination: stream });

    // Act
    await expectOk(runtime.loggerSink.emit({ level: 'info', message: 'hello' }));
    await expectOk(runtime.metricsCollector.record({ kind: 'counter', name: 'jobs', value: 2 }));
    await expectOk(runtime.traceEmitter.emit({ name: 'work' }));
    globalTracerRecords();
    await runtime.flush();

    // Assert
    runtime.active.should.eql({ logs: true, metrics: true, traces: true });
    runtime.globalRegistered.should.be.true();
    stream.lines[0]?.should.match({ ...semantic, msg: 'hello' });
    metricExporters.exporter.getMetrics()[0]?.resource.attributes.should.eql(semantic);
    traceFactories.exporter
      .getFinishedSpans()
      .map(span => span.name)
      .should.eql(['work', 'work', 'auto', 'auto']);
    traceFactories.exporter.getFinishedSpans()[0]?.resource.attributes.should.eql(semantic);
    metricExporters.otlpOptions[0]?.should.eql({
      url: 'http://127.0.0.1:4318/v1/metrics',
      headers: {},
      timeoutMillis: 10_000,
      compression: 'none',
      tls: {},
    });
    [...metricExporters.agents, ...traceFactories.agents].should.eql([{ keepAlive: true }, { keepAlive: true }]);
    runtime.resource.attributes.should.eql(semantic);
    await runtime.shutdown();
    globalTracerRecords().should.be.false();
  });

  it.each([
    ['a PT1S block interval', { ...liveBlock, metrics: { ...liveBlock.metrics, interval: 'PT1S' } }, {}],
    ['OTEL_METRIC_EXPORT_INTERVAL=1000', liveBlock, { OTEL_METRIC_EXPORT_INTERVAL: '1000' }],
  ])('should start with %s below the default export timeout', async (_label, block, environment) => {
    // Arrange
    const bootstrap = new OtelBootstrap({ metrics: new MetricSignalFactory(new RecordingMetricExporters()) });

    // Act
    const runtime = bootstrap.init(block, identity, { environment: { ...environment, OTEL_TRACES_EXPORTER: 'none' } });

    // Assert
    runtime.active.metrics.should.be.true();
    await runtime.shutdown();
  });
});

describe('OtelBootstrap uses only the injected environment', () => {
  it('should configure the real exporters and sampler from it while process variables disagree', async () => {
    // Arrange
    const traces = new CapturingSdkTraceFactories();
    const metrics = new CapturingSdkMetricExporters();
    const bootstrap = new OtelBootstrap({
      metrics: new MetricSignalFactory(metrics),
      traces: new TraceSignalFactory(traces),
    });
    const injected = {
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'http://127.0.0.1:54321/custom',
      OTEL_EXPORTER_OTLP_TIMEOUT: '1234',
      OTEL_EXPORTER_OTLP_HEADERS: 'tenant=review',
      OTEL_TRACES_SAMPLER: 'always_off',
      OTEL_TRACES_EXPORTER: 'otlp',
      OTEL_METRICS_EXPORTER: 'otlp',
    };

    // Act
    const actual = await withProcessEnv(
      {
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'http://process:4318/v1/traces',
        OTEL_EXPORTER_OTLP_METRICS_ENDPOINT: 'http://process:4318/v1/metrics',
        OTEL_EXPORTER_OTLP_TIMEOUT: '9999',
        OTEL_EXPORTER_OTLP_HEADERS: 'tenant=process',
        OTEL_TRACES_SAMPLER: 'always_on',
      },
      async () => {
        const runtime = bootstrap.init(defaultOtelBlock, identity, { environment: injected });
        const span = runtime.tracer.startSpan('sampled-out');
        const recording = span.isRecording();
        span.end();
        const settings = await Promise.all([...traces.exporters, ...metrics.exporters].map(exporterSettings));
        await runtime.shutdown();
        return { recording, settings };
      },
    );

    // Assert
    actual.recording.should.be.false();
    actual.settings
      .map(entry => [entry.url, entry.timeoutMillis, entry.headers.tenant])
      .should.eql([
        ['http://127.0.0.1:54321/custom', 1234, 'review'],
        ['http://localhost:4318/v1/metrics', 1234, 'review'],
      ]);
  });

  it('should ignore process variables entirely when the injected environment is empty', async () => {
    // Arrange
    const traces = new RecordingTraceFactories();
    const bootstrap = new OtelBootstrap({ traces: new TraceSignalFactory(traces) });

    // Act
    const runtime = await withProcessEnv({ OTEL_SDK_DISABLED: 'true', OTEL_TRACES_SAMPLER: 'always_off' }, async () =>
      bootstrap.init(liveBlock, identity, { environment: {} }),
    );
    const span = runtime.tracer.startSpan('kept');
    const recording = span.isRecording();
    span.end();
    await runtime.shutdown();

    // Assert
    runtime.active.traces.should.be.true();
    recording.should.be.true();
  });
});

describe('OtelBootstrap TLS files', () => {
  const tracesOnly = { OTEL_METRICS_EXPORTER: 'none', OTEL_TRACES_EXPORTER: 'otlp' };

  it('should read the injected certificate files into the trace agent options', async () => {
    // Arrange
    const directory = mkdtempSync(join(tmpdir(), 'otel-init-tls-'));
    writeFileSync(join(directory, 'ca.pem'), 'generic');
    writeFileSync(join(directory, 'traces.pem'), 'traces');
    const { bootstrap, traceFactories } = recordingBootstrap();

    // Act
    const runtime = bootstrap.init(liveBlock, identity, {
      environment: {
        ...tracesOnly,
        OTEL_EXPORTER_OTLP_CERTIFICATE: join(directory, 'ca.pem'),
        OTEL_EXPORTER_OTLP_TRACES_CERTIFICATE: join(directory, 'traces.pem'),
      },
    });
    await runtime.shutdown();

    // Assert
    traceFactories.agents.should.eql([{ keepAlive: true, ca: Buffer.from('traces') }]);
  });

  it('should refuse to start, naming the variable, when an injected file is unreadable', () => {
    // Arrange
    const { bootstrap, traceFactories } = recordingBootstrap();

    // Act
    const actual = (() => {
      try {
        bootstrap.init(liveBlock, identity, {
          environment: { ...tracesOnly, OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY: '/nonexistent/otel/client.key' },
        });
        return undefined;
      } catch (error) {
        return error;
      }
    })();

    // Assert
    (actual instanceof OtlpTlsFileError).should.be.true();
    (actual as OtlpTlsFileError).variable.should.eql('OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY');
    traceFactories.calls.should.eql([]);
    globalTracerRecords().should.be.false();
  });

  it('should read no file for a signal served by a seam override', async () => {
    // Arrange
    const { bootstrap } = recordingBootstrap();

    // Act
    const runtime = bootstrap.init(liveBlock, identity, {
      environment: { ...tracesOnly, OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY: '/nonexistent/otel/client.key' },
      seams: { traces: new InMemoryTraceEmitter() },
    });
    await runtime.shutdown();

    // Assert
    runtime.globalRegistered.should.be.false();
  });
});

describe('OtelBootstrap global registration ownership', () => {
  function start(): { runtime: OtelRuntime; spans: InMemorySpanExporter } {
    const { bootstrap, traceFactories } = recordingBootstrap();
    const runtime = bootstrap.init(liveBlock, identity, {
      environment: { OTEL_METRICS_EXPORTER: 'none', OTEL_TRACES_EXPORTER: 'otlp' },
    });
    return { runtime, spans: traceFactories.exporter };
  }

  it('should claim and release the globals across repeated init and shutdown', async () => {
    // Arrange
    const first = start();
    await first.runtime.shutdown();

    // Act
    const second = start();
    const auto = globalTracerRecords();
    const exported = second.spans.getFinishedSpans().map(span => span.name);
    await second.runtime.shutdown();

    // Assert
    [first.runtime.globalRegistered, second.runtime.globalRegistered, auto].should.eql([true, true, true]);
    exported.should.eql(['auto']);
    globalTracerRecords().should.be.false();
  });

  it('should leave the owner registered when a second runtime shuts down', async () => {
    // Arrange
    const owner = start();
    const guest = start();

    // Act
    await guest.runtime.shutdown();
    const ownerStillServes = globalTracerRecords();
    const exported = owner.spans.getFinishedSpans().map(span => span.name);
    await owner.runtime.shutdown();

    // Assert
    [owner.runtime.globalRegistered, guest.runtime.globalRegistered].should.eql([true, false]);
    ownerStillServes.should.be.true();
    exported.should.eql(['auto']);
    globalTracerRecords().should.be.false();
  });

  it('should keep a later owner registered when a stale runtime shuts down again', async () => {
    // Arrange
    const first = start();
    await first.runtime.shutdown();
    const second = start();

    // Act
    await first.runtime.shutdown();
    const stillServes = globalTracerRecords();
    const parent = trace.setSpanContext(context.active(), {
      traceId: 'ab'.repeat(16),
      spanId: 'cd'.repeat(8),
      traceFlags: 1,
    });
    const carried = context.with(parent, () => trace.getSpanContext(context.active())?.traceId);
    const headers: Record<string, string> = {};
    propagation.inject(parent, headers);
    const exported = second.spans.getFinishedSpans().map(span => span.name);
    await second.runtime.shutdown();

    // Assert
    second.runtime.globalRegistered.should.be.true();
    stillServes.should.be.true();
    exported.should.eql(['auto']);
    (carried ?? '').should.eql('ab'.repeat(16));
    (headers.traceparent ?? '').should.startWith('00-abab');
    globalTracerRecords().should.be.false();
  });

  it('should leave a host provider registered after a stale runtime shuts down again', async () => {
    // Arrange
    const stale = start();
    await stale.runtime.shutdown();
    const host = new InMemorySpanExporter();
    const hostProvider = new BasicTracerProvider({
      resource: resourceFromAttributes({}),
      spanProcessors: [new SimpleSpanProcessor(host)],
    });
    trace.setGlobalTracerProvider(hostProvider);

    // Act
    await stale.runtime.shutdown();
    globalTracerRecords();

    // Assert
    host
      .getFinishedSpans()
      .map(span => span.name)
      .should.eql(['auto']);
    await hostProvider.shutdown();
    trace.disable();
  });

  it('should leave a host provider untouched and still work through its own tracer', async () => {
    // Arrange
    const host = new InMemorySpanExporter();
    const hostProvider = new BasicTracerProvider({
      resource: resourceFromAttributes({}),
      spanProcessors: [new SimpleSpanProcessor(host)],
    });
    trace.setGlobalTracerProvider(hostProvider);

    // Act
    const ours = start();
    ours.runtime.tracer.startSpan('ours').end();
    globalTracerRecords();
    const exported = ours.spans.getFinishedSpans().map(span => span.name);
    await ours.runtime.shutdown();
    globalTracerRecords();

    // Assert
    ours.runtime.globalRegistered.should.be.false();
    exported.should.eql(['ours']);
    host
      .getFinishedSpans()
      .map(span => span.name)
      .should.eql(['auto', 'auto']);
    await hostProvider.shutdown();
    trace.disable();
  });
});

describe('TelemetryLifecycleError identity', () => {
  class NarrowLifecycleError extends TelemetryLifecycleError {}

  it.each([
    ['a lifecycle error', new TelemetryLifecycleError('logs', 'flush', 'x'), TelemetryLifecycleError, true],
    [
      'a branded look-alike from the other build',
      { [Symbol.for('AtomiCloud.Diene.Otel.TelemetryLifecycleError')]: true },
      TelemetryLifecycleError,
      true,
    ],
    ['a plain Error', new Error('m'), TelemetryLifecycleError, false],
    ['null', null, TelemetryLifecycleError, false],
    ['a base error against a subclass', new TelemetryLifecycleError('logs', 'flush', 'x'), NarrowLifecycleError, false],
    [
      'a subclass error against the subclass',
      new NarrowLifecycleError('traces', 'shutdown', 'x'),
      NarrowLifecycleError,
      true,
    ],
  ])('should judge %s', (_label, value, type, expected) => {
    // Arrange
    const candidate: unknown = value;

    // Act
    const actual = candidate instanceof (type as typeof TelemetryLifecycleError);

    // Assert
    actual.should.eql(expected);
  });
});
