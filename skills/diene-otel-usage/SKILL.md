---
name: diene-otel-usage
description: Use when consuming @atomicloud/diene.otel — composing the OTel config block into a service schema, initializing telemetry and shutting it down, or testing telemetry with the /test-helper harness, trace double and the interfaces logger/metrics mocks.
---

# Diene OTel usage

Import only the package root and `/test-helper`; never copy the implementation or
reach into `src/` or `dist/`. This skill is complete on its own. The full standard is
[docs/standards/otel/index.md](https://github.com/AtomiCloud/diene.bun-otel/blob/main/docs/standards/otel/index.md)
in the source repository.

## The block

The base config keeps every exporter off; a landscape overlay turns one on and sets
its endpoint.

```yaml
otel:
  logs:
    enabled: true
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ''
        protocol: http/protobuf
        headers: {}
        timeout: PT10S
  metrics:
    enabled: true
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ''
        protocol: http/protobuf
        headers: {}
        timeout: PT10S
    interval: PT60S
  traces:
    enabled: true
    sampler:
      type: parentbased_traceidratio
      ratio: 1.0
    exporter:
      console:
        enabled: false
      otlp:
        enabled: false
        endpoint: ''
        protocol: http/protobuf
        headers: {}
        timeout: PT10S
```

- Signal keys are exactly `logs`, `metrics`, `traces`; each exporter has its own `enabled`.
- OTLP is http/protobuf on port **4318**; any other port is rejected, even when disabled.
- An enabled OTLP exporter needs an endpoint. Durations are positive ISO 8601 (`PT10S`).
- `sampler.type`: `parentbased_traceidratio`, `always_on` or `always_off`; `ratio` in `[0, 1]`.

Compose the schema into your root schema in one line; `@atomicloud/diene.config`
loads and validates it:

```ts
const rootSchema = z.object({ app: appSchema, otel: otelBlockSchema });
```

## Resource identity

Built from the `app:` values; never write these by hand.

| `app:` value | Attribute                     |
| ------------ | ----------------------------- |
| landscape    | `deployment.environment.name` |
| platform     | `service.namespace`           |
| service      | `service.name`                |
| version      | `service.version`             |

All five values (including `module`) are also set as `atomi.<name>`.
`OTEL_RESOURCE_ATTRIBUTES` and then `OTEL_SERVICE_NAME` are layered on top.

## Init, flush and shutdown

1. `const runtime = new OtelBootstrap().init(config.otel, config.app);` once at startup.
   Pass `{ environment }` to choose the variables; the default is `process.env`. Only that
   record decides the setup; the header merge is the one remaining process read (the OTLP
   exporters still add header keys that only `process.env` sets).
2. Use `runtime.tracer`, `runtime.meter`, `runtime.logger` (pino), or the seams
   `runtime.traceEmitter`, `runtime.metricsCollector`, `runtime.loggerSink`.
3. The runtime registers the global tracer provider (plus context manager and propagator)
   only if none is registered; `runtime.globalRegistered` says whether it did.
4. Your framework owns `SIGTERM`: call `await runtime.shutdown()` there. It waits for every
   flush, then stops the providers, then releases only the globals it registered. Failures
   arrive as one `AggregateError` of `TelemetryLifecycleError` (each has `signal` and
   `phase`). `runtime.flush()` flushes without stopping.

Standard variables win over the block: `OTEL_SDK_DISABLED`, `OTEL_*_EXPORTER`,
`OTEL_EXPORTER_OTLP_[SIGNAL_]ENDPOINT|HEADERS|TIMEOUT|COMPRESSION`, `OTEL_TRACES_SAMPLER`
(+ `_ARG`), `OTEL_METRIC_EXPORT_INTERVAL|TIMEOUT`, `OTEL_BSP_*`,
`OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE`, `OTEL_ATTRIBUTE_*_LIMIT`,
`OTEL_SPAN_*_LIMIT` and `OTEL_EXPORTER_OTLP_[SIGNAL_]CERTIFICATE|CLIENT_CERTIFICATE|CLIENT_KEY`
(PEM files; an unreadable one fails init with `OtlpTlsFileError` naming the variable). The
metric reader timeout never exceeds its interval. Logs are pino JSON on stdout with trace ids; there is no OTLP logs
export.

Copyable examples: `assets/consumer.ts` (ESM), `assets/consumer.cjs` (CJS).

## Testing

- Never start a collector in unit or integration tests. Inject the shared mocks.
- `InMemoryLoggerSink`, `InMemoryMetricsCollector` and their assertions come from
  `@atomicloud/diene.interfaces/test-helper`. This package does not re-export them.
- From `@atomicloud/diene.otel/test-helper`:
  - `OtelTestHarness().start(block?, identity?, environment?)` inits with the logger and
    metrics mocks and an `InMemoryTraceEmitter` injected and returns them.
  - `OtelAssertions`: `traceRecords`, `traceCalls`, `resourceAttributes`, `identityResource`,
    `payload`. They throw `OtelAssertionError`, also on values JSON cannot carry (`NaN`,
    `undefined`, functions, …).
  - `OtelBlockFixtures`: `canonical()`, `disabled()`, `console()`, `otlp()`.
  - `AppIdentityBuilder`: a valid identity, `with(...)`, `attributes()`.

```ts
const run = new OtelTestHarness().start(new OtelBlockFixtures().otlp());
await serviceUnderTest(run.runtime);
assertLogRecords(run.logger, [{ level: 'info', message: 'charged' }]);
new OtelAssertions().traceRecords(run.traces, [{ name: 'charge', status: 'ok' }]);
await run.runtime.shutdown();
```

More in `assets/test-helper.md`.
