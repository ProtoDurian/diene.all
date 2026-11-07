import { OtelBootstrap, otelBlockSchema } from '@atomicloud/diene.otel';

const otel = otelBlockSchema.parse({
  logs: { enabled: true, exporter: { console: { enabled: true }, otlp: exporterOff() } },
  metrics: { enabled: true, interval: 'PT60S', exporter: { console: { enabled: false }, otlp: exporterOn() } },
  traces: {
    enabled: true,
    sampler: { type: 'parentbased_traceidratio', ratio: 0.25 },
    exporter: { console: { enabled: false }, otlp: exporterOn() },
  },
});
const app = { landscape: 'lapras', platform: 'atomi', service: 'sample', module: 'api', version: '1.0.0' };

const runtime = new OtelBootstrap().init(otel, app);
runtime.logger.info({ port: 8080 }, 'listening');
await runtime.metricsCollector.record({ kind: 'counter', name: 'requests', value: 1 }).unwrap();
runtime.tracer.startActiveSpan('startup', span => span.end());

process.on('SIGTERM', () => {
  runtime.shutdown().finally(() => process.exit(0));
});

function exporterOn() {
  return { ...exporterOff(), enabled: true, endpoint: 'http://otel-collector:4318' };
}

function exporterOff() {
  return { enabled: false, endpoint: '', protocol: 'http/protobuf' as const, headers: {}, timeout: 'PT10S' };
}
