import { z } from 'zod';
import { FIXED_DURATION_ERROR, WireDurationConverter } from './duration.js';
import { OtlpEndpointPolicy } from './endpoint.js';

class OtelSchemaFactory {
  constructor(
    private readonly durations: WireDurationConverter,
    private readonly endpoints: OtlpEndpointPolicy,
  ) {}

  duration() {
    return z.string().superRefine((value, context) => {
      try {
        this.durations.toMilliseconds(value);
      } catch (error) {
        context.addIssue({ code: 'custom', message: error instanceof Error ? error.message : FIXED_DURATION_ERROR });
      }
    });
  }

  consoleExporter() {
    return z.object({ enabled: z.boolean() }).strict().readonly();
  }

  otlpExporter() {
    return z
      .object({
        enabled: z.boolean(),
        endpoint: z.string(),
        protocol: z.literal('http/protobuf'),
        headers: z.record(z.string(), z.string()),
        timeout: this.duration(),
      })
      .strict()
      .superRefine((value, context) => {
        if (value.enabled && value.endpoint === '') {
          context.addIssue({
            code: 'custom',
            message: 'Enabled OTLP exporters require an endpoint',
            path: ['endpoint'],
          });
        }
        if (value.endpoint !== '' && !this.endpoints.accepts(value.endpoint)) {
          context.addIssue({
            code: 'custom',
            message: 'OTLP endpoint must be an HTTP(S) URL with explicit port 4318',
            path: ['endpoint'],
          });
        }
      })
      .readonly();
  }

  exporter() {
    return z.object({ console: this.consoleExporter(), otlp: this.otlpExporter() }).strict().readonly();
  }

  logs() {
    return z.object({ enabled: z.boolean(), exporter: this.exporter() }).strict().readonly();
  }

  metrics() {
    return z.object({ enabled: z.boolean(), exporter: this.exporter(), interval: this.duration() }).strict().readonly();
  }

  sampler() {
    return z
      .object({
        type: z.enum(['parentbased_traceidratio', 'always_on', 'always_off']),
        ratio: z.number().finite().min(0).max(1),
      })
      .strict()
      .readonly();
  }

  traces() {
    return z.object({ enabled: z.boolean(), sampler: this.sampler(), exporter: this.exporter() }).strict().readonly();
  }

  block() {
    return z.object({ logs: this.logs(), metrics: this.metrics(), traces: this.traces() }).strict().readonly();
  }
}

const otelSchemas = new OtelSchemaFactory(new WireDurationConverter(), new OtlpEndpointPolicy());

const wireDurationSchema = otelSchemas.duration();
const otelConsoleExporterSchema = otelSchemas.consoleExporter();
const otelOtlpExporterSchema = otelSchemas.otlpExporter();
const otelExporterSchema = otelSchemas.exporter();
const otelLogsSchema = otelSchemas.logs();
const otelMetricsSchema = otelSchemas.metrics();
const otelSamplerSchema = otelSchemas.sampler();
const otelTracesSchema = otelSchemas.traces();
const otelBlockSchema = otelSchemas.block();

type OtelConsoleExporter = z.infer<typeof otelConsoleExporterSchema>;
type OtelOtlpExporter = z.infer<typeof otelOtlpExporterSchema>;
type OtelExporter = z.infer<typeof otelExporterSchema>;
type OtelLogs = z.infer<typeof otelLogsSchema>;
type OtelMetrics = z.infer<typeof otelMetricsSchema>;
type OtelSampler = z.infer<typeof otelSamplerSchema>;
type OtelTraces = z.infer<typeof otelTracesSchema>;
type OtelBlock = z.infer<typeof otelBlockSchema>;

const disabledExporter = Object.freeze({
  console: Object.freeze({ enabled: false }),
  otlp: Object.freeze({
    enabled: false,
    endpoint: '',
    headers: Object.freeze({}),
    protocol: 'http/protobuf' as const,
    timeout: 'PT10S',
  }),
});

const defaultOtelBlock = Object.freeze({
  logs: Object.freeze({ enabled: true, exporter: disabledExporter }),
  metrics: Object.freeze({ enabled: true, exporter: disabledExporter, interval: 'PT60S' }),
  traces: Object.freeze({
    enabled: true,
    exporter: disabledExporter,
    sampler: Object.freeze({ ratio: 1, type: 'parentbased_traceidratio' as const }),
  }),
}) satisfies OtelBlock;

export type {
  OtelBlock,
  OtelConsoleExporter,
  OtelExporter,
  OtelLogs,
  OtelMetrics,
  OtelOtlpExporter,
  OtelSampler,
  OtelTraces,
};
export {
  defaultOtelBlock,
  OtelSchemaFactory,
  otelBlockSchema,
  otelConsoleExporterSchema,
  otelExporterSchema,
  otelLogsSchema,
  otelMetricsSchema,
  otelOtlpExporterSchema,
  otelSamplerSchema,
  otelTracesSchema,
  wireDurationSchema,
};
