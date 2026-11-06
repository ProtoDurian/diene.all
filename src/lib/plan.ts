import type { TelemetryAttributes } from '@atomicloud/diene.interfaces';
import type { Resource } from '@opentelemetry/resources';
import type { Sampler } from '@opentelemetry/sdk-trace-base';
import { WireDurationConverter } from './duration.js';
import { OtlpEndpointPolicy, type OtlpExporterOptions, OtlpExporterOptionsFactory } from './endpoint.js';
import { ExporterSelector, OtelEnvironment, type SignalFlags, type SignalSelections } from './environment.js';
import { type AppIdentity, appIdentitySchema, ResourceIdentityMapper } from './resource.js';
import { TraceSamplerFactory } from './sampler.js';
import { type OtelBlock, otelBlockSchema } from './schema.js';

type MetricTemporality = 'cumulative' | 'delta' | 'lowmemory';

interface SpanBatchSettings {
  readonly exportTimeoutMillis: number;
  readonly maxExportBatchSize: number;
  readonly maxQueueSize: number;
  readonly scheduledDelayMillis: number;
}

interface OtelPlan {
  readonly block: OtelBlock;
  readonly identity: AppIdentity;
  readonly live: SignalFlags;
  readonly selections: SignalSelections;
  readonly resourceAttributes: TelemetryAttributes;
  readonly resource: Resource;
  readonly metrics: Readonly<{
    intervalMillis: number;
    timeoutMillis: number;
    temporality: MetricTemporality;
    otlp: OtlpExporterOptions;
  }>;
  readonly traces: Readonly<{ sampler: Sampler; batch: SpanBatchSettings; otlp: OtlpExporterOptions }>;
}

const TEMPORALITIES: readonly string[] = ['cumulative', 'delta', 'lowmemory'];

class OtelPlanner {
  constructor(
    private readonly selector: ExporterSelector = new ExporterSelector(),
    private readonly resources: ResourceIdentityMapper = new ResourceIdentityMapper(),
    private readonly samplers: TraceSamplerFactory = new TraceSamplerFactory(),
    private readonly durations: WireDurationConverter = new WireDurationConverter(),
    private readonly exporters: OtlpExporterOptionsFactory = new OtlpExporterOptionsFactory(
      durations,
      new OtlpEndpointPolicy(),
    ),
  ) {}

  plan(block: OtelBlock, identity: AppIdentity, values: Readonly<Record<string, string | undefined>>): OtelPlan {
    const environment = new OtelEnvironment(values);
    const validBlock = otelBlockSchema.parse(block);
    const validIdentity = appIdentitySchema.parse(identity);
    const intervalMillis =
      environment.positiveInteger('OTEL_METRIC_EXPORT_INTERVAL') ??
      this.durations.toMilliseconds(validBlock.metrics.interval);
    const timeoutMillis =
      environment.positiveInteger('OTEL_METRIC_EXPORT_TIMEOUT') ??
      this.durations.toMilliseconds(validBlock.metrics.exporter.otlp.timeout);
    const temporality = environment.value('OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE')?.toLowerCase() ?? '';
    return Object.freeze({
      block: validBlock,
      identity: validIdentity,
      live: this.selector.live(validBlock, environment),
      selections: this.selector.selectAll(validBlock, environment),
      resourceAttributes: this.resources.attributes(validIdentity, environment),
      resource: this.resources.resource(validIdentity, environment),
      metrics: Object.freeze({
        intervalMillis,
        timeoutMillis: Math.min(timeoutMillis, intervalMillis),
        temporality: (TEMPORALITIES.includes(temporality) ? temporality : 'cumulative') as MetricTemporality,
        otlp: this.exporters.create(validBlock.metrics.exporter.otlp, 'metrics', environment),
      }),
      traces: Object.freeze({
        sampler: this.samplers.create(validBlock.traces.sampler, environment),
        batch: Object.freeze({
          exportTimeoutMillis: environment.positiveInteger('OTEL_BSP_EXPORT_TIMEOUT') ?? 30_000,
          maxExportBatchSize: environment.positiveInteger('OTEL_BSP_MAX_EXPORT_BATCH_SIZE') ?? 512,
          maxQueueSize: environment.positiveInteger('OTEL_BSP_MAX_QUEUE_SIZE') ?? 2048,
          scheduledDelayMillis: environment.positiveInteger('OTEL_BSP_SCHEDULE_DELAY') ?? 5000,
        }),
        otlp: this.exporters.create(validBlock.traces.exporter.otlp, 'traces', environment),
      }),
    });
  }
}

export type { MetricTemporality, OtelPlan, SpanBatchSettings };
export { OtelPlanner };
