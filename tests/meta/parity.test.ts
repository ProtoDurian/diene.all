import { afterAll, describe, it } from 'bun:test';
import { InMemoryLoggerSink, InMemoryMetricsCollector } from '@atomicloud/diene.interfaces/test-helper';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { AggregationTemporality, InMemoryMetricExporter } from '@opentelemetry/sdk-metrics';
import { BasicTracerProvider, InMemorySpanExporter, SimpleSpanProcessor } from '@opentelemetry/sdk-trace-base';
import 'should';
import { LoggerSignalFactory } from '../../src/adapters/signals/logs';
import { MetricSignalFactory } from '../../src/adapters/signals/metrics';
import { SdkTraceEmitter } from '../../src/adapters/signals/traces';
import { InMemoryTraceEmitter } from '../../src/test-helper';
import { runSeamScenarios, type Seams } from './contract/behaviours';

const resource = resourceFromAttributes({ 'service.name': 'svc' });
const metricExporter = new InMemoryMetricExporter(AggregationTemporality.CUMULATIVE);
const spanExporter = new InMemorySpanExporter();
const traceProvider = new BasicTracerProvider({ resource, spanProcessors: [new SimpleSpanProcessor(spanExporter)] });
const metricSignal = new MetricSignalFactory({
  console: () => metricExporter,
  otlp: () => metricExporter,
}).create({
  selection: { console: true, otlp: false },
  resource,
  scope: { name: 'svc', version: '1.0.0' },
  settings: {
    intervalMillis: 60_000,
    timeoutMillis: 1_000,
    temporality: 'cumulative',
    otlp: { url: 'http://127.0.0.1:4318/v1/metrics', headers: {}, timeoutMillis: 1_000, compression: 'none' },
  },
});

function realSeams(): Seams {
  return {
    logger: new LoggerSignalFactory().create(true, {}, { write: () => undefined }).sink,
    metrics: metricSignal.collector,
    traces: new SdkTraceEmitter(traceProvider.getTracer('svc'), traceProvider),
  };
}

function mockSeams(): Seams {
  return {
    logger: new InMemoryLoggerSink(),
    metrics: new InMemoryMetricsCollector(),
    traces: new InMemoryTraceEmitter(),
  };
}

afterAll(async () => {
  await Promise.all([metricSignal.provider?.shutdown(), traceProvider.shutdown()]);
});

describe('seam contract parity', () => {
  it('should give the same outcomes from the SDK-backed seams and the in-memory doubles', async () => {
    // Arrange
    const real = realSeams();
    const mock = mockSeams();

    // Act
    const actual = await runSeamScenarios(real);
    const expected = await runSeamScenarios(mock);

    // Assert
    actual.should.eql(expected);
    actual
      .map(entry => (entry === 'ok' ? 'ok' : entry.code))
      .should.eql(['ok', 'invalid-input', 'ok', 'ok', 'invalid-input', 'ok', 'ok', 'invalid-input', 'ok']);
  });

  it('should record the same accepted trace on both sides', async () => {
    // Arrange
    const real = realSeams();
    const mock = new InMemoryTraceEmitter();
    const record = { name: 'checkout', attributes: { order: 1 }, events: [{ name: 'paid' }] };

    // Act
    await real.traces.emit(record).unwrap();
    await mock.emit(record).unwrap();

    // Assert
    const span = spanExporter.getFinishedSpans().find(finished => finished.name === 'checkout');
    span?.attributes.should.eql(mock.records[0]?.attributes);
    span?.events.map(event => event.name).should.eql(mock.records[0]?.events?.map(event => event.name));
  });
});
