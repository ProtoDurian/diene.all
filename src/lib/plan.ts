import type { TelemetryAttributes } from '@atomicloud/diene.interfaces';
import type { Resource } from '@opentelemetry/resources';
import type { Sampler } from '@opentelemetry/sdk-trace-base';
import { WireDurationConverter } from './duration.js';
import { OtlpEndpointPolicy, type OtlpExporterOptions, OtlpExporterOptionsFactory } from './endpoint.js';
import { ExporterSelector, OtelEnvironment, type SignalFlags, type SignalSelections } from './environment.js';
import { type AppIdentity, appIdentitySchema, ResourceIdentityMapper } from './resource.js';
import { TraceSamplerFactory } from './sampler.js';
import { type OtelBlock, type OtelMetrics, otelBlockSchema } from './schema.js';

interface OtelPlan {
  readonly block: OtelBlock;
  readonly identity: AppIdentity;
  readonly live: SignalFlags;
  readonly selections: SignalSelections;
  readonly resourceAttributes: TelemetryAttributes;
  readonly resource: Resource;
  readonly metrics: Readonly<{ intervalMillis: number; timeoutMillis: number; otlp: OtlpExporterOptions }>;
  readonly traces: Readonly<{ sampler: Sampler | undefined; otlp: OtlpExporterOptions }>;
}

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
    return Object.freeze({
      block: validBlock,
      identity: validIdentity,
      live: this.selector.live(validBlock, environment),
      selections: this.selector.selectAll(validBlock, environment),
      resourceAttributes: this.resources.attributes(validIdentity, environment),
      resource: this.resources.resource(validIdentity, environment),
      metrics: Object.freeze({
        intervalMillis: this.metricMillis(environment, 'OTEL_METRIC_EXPORT_INTERVAL', validBlock.metrics.interval),
        timeoutMillis: this.metricMillis(
          environment,
          'OTEL_METRIC_EXPORT_TIMEOUT',
          validBlock.metrics.exporter.otlp.timeout,
        ),
        otlp: this.exporters.create(validBlock.metrics.exporter.otlp, 'metrics', environment),
      }),
      traces: Object.freeze({
        sampler: this.samplers.create(validBlock.traces.sampler, environment),
        otlp: this.exporters.create(validBlock.traces.exporter.otlp, 'traces', environment),
      }),
    });
  }

  private metricMillis(environment: OtelEnvironment, variable: string, fallback: OtelMetrics['interval']): number {
    const override = environment.value(variable);
    if (override !== undefined && /^\d+$/.test(override) && Number(override) > 0) return Number(override);
    return this.durations.toMilliseconds(fallback);
  }
}

export type { OtelPlan };
export { OtelPlanner };
