import type { AgentOptions } from 'node:https';
import {
  checkMetricRecord,
  type MetricRecord,
  type MetricsCollector,
  type MetricsError,
  portError,
} from '@atomicloud/diene.interfaces';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { type Counter, createNoopMeter, type Gauge, type Histogram, type Meter } from '@opentelemetry/api';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-proto';
import type { Resource } from '@opentelemetry/resources';
import {
  AggregationTemporality,
  ConsoleMetricExporter,
  MeterProvider,
  PeriodicExportingMetricReader,
  type PushMetricExporter,
} from '@opentelemetry/sdk-metrics';
import type { OtlpExporterOptions } from '../../lib/endpoint.js';
import type { ExporterSelection } from '../../lib/environment.js';
import type { MetricTemporality, OtelPlan } from '../../lib/plan.js';

type Instrument = Counter | Gauge | Histogram;
type OtlpMetricExporterConfig = NonNullable<ConstructorParameters<typeof OTLPMetricExporter>[0]>;

const TEMPORALITY: Readonly<Record<MetricTemporality, number>> = Object.freeze({
  cumulative: AggregationTemporality.CUMULATIVE,
  delta: AggregationTemporality.DELTA,
  lowmemory: 2,
});

interface MetricExporterFactories {
  console(): PushMetricExporter;
  otlp(options: OtlpExporterOptions, temporality: MetricTemporality, agent: AgentOptions): PushMetricExporter;
}

interface MetricSignal {
  readonly active: boolean;
  readonly collector: MetricsCollector;
  readonly meter: Meter;
  readonly provider?: MeterProvider;
}

interface MetricSignalInput {
  readonly agent: AgentOptions;
  readonly selection: ExporterSelection;
  readonly resource: Resource;
  readonly scope: Readonly<{ name: string; version: string }>;
  readonly settings: OtelPlan['metrics'];
}

class SdkMetricExporterFactories implements MetricExporterFactories {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  console(): PushMetricExporter {
    return new ConsoleMetricExporter();
  }

  otlp(options: OtlpExporterOptions, temporality: MetricTemporality, agent: AgentOptions): PushMetricExporter {
    return new OTLPMetricExporter({
      compression: options.compression as NonNullable<OtlpMetricExporterConfig['compression']>,
      headers: { ...options.headers },
      httpAgentOptions: agent,
      timeoutMillis: options.timeoutMillis,
      url: options.url,
      temporalityPreference: TEMPORALITY[temporality] as NonNullable<OtlpMetricExporterConfig['temporalityPreference']>,
    });
  }
}

class SdkMetricsCollector implements MetricsCollector {
  constructor(
    private readonly meter: Meter,
    private readonly provider?: MeterProvider,
  ) {}

  record(metric: MetricRecord): Result<void, MetricsError> {
    const checked = checkMetricRecord(metric);
    if (!checked.ok) return Err(checked.error);
    if (this.provider === undefined) return Ok(undefined);
    const valid = checked.value;
    try {
      const instrument = this.instrument(valid);
      if ('add' in instrument) instrument.add(valid.value, valid.attributes);
      else instrument.record(valid.value, valid.attributes);
      return Ok(undefined);
    } catch (cause) {
      return Err(this.failure('record', 'OpenTelemetry failed to record the metric', cause));
    }
  }

  flush(): Result<void, MetricsError> {
    return Res.fromSerial<void, MetricsError>(
      (async () => {
        try {
          await this.provider?.forceFlush();
          return ['ok', undefined];
        } catch (cause) {
          return ['err', this.failure('flush', 'OpenTelemetry failed to flush metrics', cause)];
        }
      })(),
    );
  }

  private instrument(metric: Readonly<MetricRecord>): Instrument {
    const options = { unit: metric.unit };
    return metric.kind === 'counter'
      ? this.meter.createCounter(metric.name, options)
      : metric.kind === 'gauge'
        ? this.meter.createGauge(metric.name, options)
        : this.meter.createHistogram(metric.name, options);
  }

  private failure(operation: string, message: string, cause: unknown): MetricsError {
    return portError('metrics', 'io', operation, message, {
      cause: cause instanceof Error ? cause.message : String(cause),
    });
  }
}

class MetricSignalFactory {
  constructor(private readonly exporters: MetricExporterFactories = new SdkMetricExporterFactories()) {}

  inactive(): MetricSignal {
    const meter = createNoopMeter();
    return Object.freeze({ active: false, collector: new SdkMetricsCollector(meter), meter });
  }

  create(input: MetricSignalInput): MetricSignal {
    const exporters = [
      ...(input.selection.console ? [this.exporters.console()] : []),
      ...(input.selection.otlp
        ? [this.exporters.otlp(input.settings.otlp, input.settings.temporality, input.agent)]
        : []),
    ];
    if (exporters.length === 0) return this.inactive();
    const readers = exporters.map(
      exporter =>
        new PeriodicExportingMetricReader({
          exporter,
          exportIntervalMillis: input.settings.intervalMillis,
          exportTimeoutMillis: input.settings.timeoutMillis,
        }),
    );
    const provider = new MeterProvider({ readers, resource: input.resource });
    const meter = provider.getMeter(input.scope.name, input.scope.version);
    return Object.freeze({ active: true, collector: new SdkMetricsCollector(meter, provider), meter, provider });
  }
}

export type { MetricExporterFactories, MetricSignal, MetricSignalInput };
export { MetricSignalFactory, SdkMetricExporterFactories, SdkMetricsCollector };
