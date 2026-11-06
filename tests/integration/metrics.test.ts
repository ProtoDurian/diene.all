import { describe, it } from 'bun:test';
import { InMemoryMetricsCollector } from '@atomicloud/diene.interfaces/test-helper';
import { createNoopMeter } from '@opentelemetry/api';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-proto';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
  AggregationTemporality,
  ConsoleMetricExporter,
  InMemoryMetricExporter,
  MeterProvider,
  PeriodicExportingMetricReader,
} from '@opentelemetry/sdk-metrics';
import 'should';
import {
  MetricSignalFactory,
  SdkMetricExporterFactories,
  SdkMetricsCollector,
} from '../../src/adapters/signals/metrics';
import { FailingMetricExporter, RecordingMetricExporters, throwingMeter } from './support/doubles';
import { expectErr, expectOk } from './support/result';

const resource = resourceFromAttributes({ 'service.name': 'svc' });
const scope = { name: 'svc', version: '1.0.0' };
const settings = { intervalMillis: 60_000, timeoutMillis: 1_000, otlp: { url: 'http://127.0.0.1:4318/v1/metrics' } };

function realProvider(exporter = new InMemoryMetricExporter(AggregationTemporality.CUMULATIVE)) {
  const reader = new PeriodicExportingMetricReader({ exporter, exportIntervalMillis: 60_000 });
  return { exporter, provider: new MeterProvider({ readers: [reader], resource }) };
}

describe('SdkMetricExporterFactories', () => {
  it('should build the console and OTLP proto exporters without exporting', async () => {
    // Arrange
    const factories = new SdkMetricExporterFactories();

    // Act
    const consoleExporter = factories.console();
    const otlpExporter = factories.otlp(settings.otlp);

    // Assert
    (consoleExporter instanceof ConsoleMetricExporter).should.be.true();
    (otlpExporter instanceof OTLPMetricExporter).should.be.true();
    await Promise.all([consoleExporter.shutdown(), otlpExporter.shutdown()]);
  });
});

describe('SdkMetricsCollector', () => {
  it('should record each instrument kind into the meter provider', async () => {
    // Arrange
    const { exporter, provider } = realProvider();
    const collector = new SdkMetricsCollector(provider.getMeter('svc'), provider);

    // Act
    await expectOk(collector.record({ kind: 'counter', name: 'jobs', value: 2, attributes: { queue: 'a' } }));
    await expectOk(collector.record({ kind: 'counter', name: 'jobs', value: 3, attributes: { queue: 'a' } }));
    await expectOk(collector.record({ kind: 'gauge', name: 'depth', value: 5, unit: '{item}' }));
    await expectOk(collector.record({ kind: 'histogram', name: 'latency', value: 12, unit: 'ms' }));
    await expectOk(collector.flush());

    // Assert
    const metrics =
      exporter
        .getMetrics()
        .at(-1)
        ?.scopeMetrics.flatMap(scoped => scoped.metrics) ?? [];
    metrics.map(metric => metric.descriptor.name).should.eql(['jobs', 'depth', 'latency']);
    metrics[0]?.dataPoints[0]?.value.should.eql(5);
    metrics[1]?.descriptor.unit.should.eql('{item}');
    await provider.shutdown();
  });

  it('should reject an invalid metric the same way the shared mock does', async () => {
    // Arrange
    const collector = new SdkMetricsCollector(createNoopMeter());
    const metric = { kind: 'counter', name: '', value: 1 } as const;

    // Act
    const actual = await expectErr(collector.record(metric));
    const expected = await expectErr(new InMemoryMetricsCollector().record(metric));

    // Assert
    actual.should.match({ port: 'metrics', code: expected.code, message: expected.message });
  });

  it('should validate and drop records without a provider', async () => {
    // Arrange
    const collector = new SdkMetricsCollector(throwingMeter());

    // Act
    const recorded = await expectOk(collector.record({ kind: 'gauge', name: 'g', value: 1 }));
    const flushed = await expectOk(collector.flush());

    // Assert
    [recorded, flushed].should.eql([undefined, undefined]);
  });

  it.each([
    ['an Error', new Error('instrument creation failed'), 'instrument creation failed'],
    ['a non-Error', 'nope', 'nope'],
  ])('should turn %s from the meter into an io error', async (_label, thrown, cause) => {
    // Arrange
    const meter = {
      createCounter: () => {
        throw thrown;
      },
    } as never;
    const collector = new SdkMetricsCollector(meter, realProvider().provider);

    // Act
    const actual = await expectErr(collector.record({ kind: 'counter', name: 'c', value: 1 }));

    // Assert
    actual.should.match({ code: 'io', operation: 'record', details: { cause } });
  });

  it('should turn a failed provider flush into an io error', async () => {
    // Arrange
    const { provider } = realProvider(new FailingMetricExporter() as never);
    const collector = new SdkMetricsCollector(provider.getMeter('svc'), provider);
    await expectOk(collector.record({ kind: 'counter', name: 'c', value: 1 }));

    // Act
    const actual = await expectErr(collector.flush());

    // Assert
    actual.should.match({ code: 'io', operation: 'flush', message: 'OpenTelemetry failed to flush metrics' });
  });
});

describe('MetricSignalFactory', () => {
  it('should stay inactive and build no exporter when none is selected', () => {
    // Arrange
    const exporters = new RecordingMetricExporters();

    // Act
    const signal = new MetricSignalFactory(exporters).create({
      selection: { console: false, otlp: false },
      resource,
      scope,
      settings,
    });

    // Assert
    signal.active.should.be.false();
    (signal.provider === undefined).should.be.true();
    exporters.calls.should.eql([]);
  });

  it('should build one reader per selected exporter on a resource-bearing provider', async () => {
    // Arrange
    const exporters = new RecordingMetricExporters();
    const signal = new MetricSignalFactory(exporters).create({
      selection: { console: true, otlp: true },
      resource,
      scope,
      settings,
    });

    // Act
    await expectOk(signal.collector.record({ kind: 'counter', name: 'c', value: 1 }));
    await expectOk(signal.collector.flush());

    // Assert
    signal.active.should.be.true();
    exporters.calls.should.eql(['console', 'otlp']);
    exporters.otlpOptions.should.eql([settings.otlp]);
    const exported = exporters.exporter.getMetrics();
    exported.length.should.eql(2);
    exported[0]?.resource.attributes.should.eql({ 'service.name': 'svc' });
    exported[0]?.scopeMetrics[0]?.scope.should.match(scope);
    await signal.provider?.shutdown();
  });

  it('should default to the SDK exporters', async () => {
    // Arrange
    const factory = new MetricSignalFactory();

    // Act
    const signal = factory.create({ selection: { console: true, otlp: false }, resource, scope, settings });

    // Assert
    signal.active.should.be.true();
    await signal.provider?.shutdown();
  });
});
