---
name: diene-otel-usage
description: Use when consuming @atomicloud/diene.otel — composing the OTel config block into a service schema, initializing telemetry and shutting it down, or testing telemetry with the /test-helper harness, trace double and the interfaces logger/metrics mocks.
---

# Diene OTel usage

Import only the package root and `/test-helper`; never copy the implementation or
reach into `src/` or `dist/`. The full contract lives in
`docs/standards/otel/index.md` of the library's source repository.

## The block

Signal keys are exactly `logs`, `metrics` and `traces`. Each exporter (`console`,
`otlp`) has its own `enabled` flag. OTLP is http/protobuf on port **4318**; any other
port is rejected. Durations are ISO 8601 (`PT10S`). The base config keeps every
exporter off; a landscape overlay turns one on and sets its endpoint.

Compose the schema into your root schema in one line; `@atomicloud/diene.config`
loads and validates it:

```ts
const rootSchema = z.object({ app: appSchema, otel: otelBlockSchema });
```

## Init and shutdown

1. `const runtime = new OtelBootstrap().init(config.otel, config.app);` once at startup.
   Keep the runtime; do not build your own global providers.
2. Use `runtime.tracer`, `runtime.meter`, `runtime.logger` (pino), or the seams
   `runtime.traceEmitter`, `runtime.metricsCollector`, `runtime.loggerSink`.
3. Your framework owns `SIGTERM`: call `await runtime.shutdown()` there. The library
   registers no signal handlers. `runtime.flush()` flushes without stopping.

Standard `OTEL_*` variables win over the block (`OTEL_SDK_DISABLED`,
`OTEL_TRACES_EXPORTER`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_SAMPLER`, …).
Logs are pino JSON on stdout with trace ids; there is no OTLP logs export.

Copyable examples: `assets/consumer.ts` (ESM), `assets/consumer.cjs` (CJS).

## Testing

- Never start a collector in unit or integration tests. Inject the shared mocks.
- `InMemoryLoggerSink`, `InMemoryMetricsCollector` and their assertions come from
  `@atomicloud/diene.interfaces/test-helper`. This package does not re-export them.
- `InMemoryTraceEmitter`, `OtelAssertions`, `OtelBlockFixtures`, `AppIdentityBuilder`
  and `OtelTestHarness` come from `@atomicloud/diene.otel/test-helper`.

See `assets/test-helper.md` for the harness and the assertions.
