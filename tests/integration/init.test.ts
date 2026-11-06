import { afterEach, describe, it } from 'bun:test';
import { portError } from '@atomicloud/diene.interfaces';
import {
  assertLogRecords,
  assertMetricRecords,
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
} from '@atomicloud/diene.interfaces/test-helper';
import { trace } from '@opentelemetry/api';
import 'should';
import { OtelBootstrap } from '../../src/adapters/init';
import { LoggerSignalFactory } from '../../src/adapters/signals/logs';
import { MetricSignalFactory } from '../../src/adapters/signals/metrics';
import { TraceSignalFactory } from '../../src/adapters/signals/traces';
import type { AppIdentity } from '../../src/lib/resource';
import { defaultOtelBlock, type OtelBlock } from '../../src/lib/schema';
import { TraceError } from '../../src/lib/trace-seam';
import { InMemoryTraceEmitter } from '../../src/test-helper/helper';
import { CaptureStream, RecordingMetricExporters, RecordingTraceFactories } from './support/doubles';
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

function recordingBootstrap(failures: { flush?: boolean; shutdown?: boolean } = {}) {
  const metricExporters = new RecordingMetricExporters();
  const traceFactories = new RecordingTraceFactories(failures);
  const bootstrap = new OtelBootstrap({
    logs: new LoggerSignalFactory(),
    metrics: new MetricSignalFactory(metricExporters),
    traces: new TraceSignalFactory(traceFactories),
  });
  return { bootstrap, metricExporters, traceFactories };
}

afterEach(() => trace.disable());

describe('OtelBootstrap off by default', () => {
  it('should build no provider and stay inactive for the canonical block', async () => {
    // Arrange
    const { bootstrap, metricExporters, traceFactories } = recordingBootstrap();

    // Act
    const runtime = bootstrap.init(defaultOtelBlock, identity, { environment: {} });
    await runtime.flush();
    await runtime.shutdown();

    // Assert
    runtime.active.should.eql({ logs: false, metrics: false, traces: false });
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
    metricExporters.calls.should.eql([]);
    traceFactories.calls.should.eql([]);
    runtime.resourceAttributes.should.eql(semantic);
  });

  it('should keep a flush failure from a seam as a shutdown failure', async () => {
    // Arrange
    const traces = new InMemoryTraceEmitter();
    const runtime = new OtelBootstrap().init(liveBlock, identity, { environment: {}, seams: { traces } });
    traces.failNext(new TraceError('io', 'flush', 'trace flush failed'));

    // Act
    const failure = await runtime.shutdown().catch((error: unknown) => error);

    // Assert
    (failure instanceof AggregateError).should.be.true();
    (failure as AggregateError).errors.length.should.eql(1);
    await runtime.shutdown();
    trace.disable();
  });
});

describe('OtelBootstrap with SDK pipelines', () => {
  it('should export metrics and spans on the mapped resource and log with the resource', async () => {
    // Arrange
    const { metricExporters, traceFactories } = recordingBootstrap();
    const stream = new CaptureStream();
    const bootstrap = new OtelBootstrap({
      metrics: new MetricSignalFactory(metricExporters),
      traces: new TraceSignalFactory(traceFactories),
    });
    const runtime = bootstrap.init(liveBlock, identity, { environment: {}, destination: stream });

    // Act
    await expectOk(runtime.loggerSink.emit({ level: 'info', message: 'hello' }));
    await expectOk(runtime.metricsCollector.record({ kind: 'counter', name: 'jobs', value: 2 }));
    await expectOk(runtime.traceEmitter.emit({ name: 'work' }));
    await runtime.flush();

    // Assert
    runtime.active.should.eql({ logs: true, metrics: true, traces: true });
    stream.lines[0]?.should.match({ ...semantic, msg: 'hello' });
    metricExporters.exporter.getMetrics()[0]?.resource.attributes.should.eql(semantic);
    traceFactories.exporter.getFinishedSpans()[0]?.resource.attributes.should.eql(semantic);
    metricExporters.otlpOptions[0]?.should.eql({
      url: 'http://127.0.0.1:4318/v1/metrics',
      headers: {},
      timeoutMillis: 10_000,
    });
    runtime.tracer.should.not.be.undefined();
    runtime.meter.should.not.be.undefined();
    runtime.logger.should.not.be.undefined();
    runtime.resource.attributes.should.eql(semantic);
    await runtime.shutdown();
  });

  it('should collect every provider shutdown failure into one AggregateError', async () => {
    // Arrange
    const { bootstrap } = recordingBootstrap({ flush: true, shutdown: true });
    const metrics = new InMemoryMetricsCollector();
    metrics.failNext(portError('metrics', 'io', 'flush', 'metric flush failed'));
    const runtime = bootstrap.init(liveBlock, identity, { environment: {}, seams: { metrics } });

    // Act
    const failure = await runtime.shutdown().catch((error: unknown) => error);

    // Assert
    (failure instanceof AggregateError).should.be.true();
    (failure as AggregateError).message.should.eql('OpenTelemetry shutdown failed');
    (failure as AggregateError).errors.length.should.eql(2);
  });
});
