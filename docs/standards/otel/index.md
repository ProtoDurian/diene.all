# OpenTelemetry

`@atomicloud/diene.otel` owns OpenTelemetry for the Bun family: the config block
schema, the resource identity, the signal lifecycle, the standard `OTEL_*`
override rules, pino logs with trace ids, and the trace seam. It ships the schema,
the SDK-backed implementations and framework-free test doubles. It loads no config
files and picks no landscape endpoints.

The .NET and Go otel libraries implement the same block and the same rules. This
standard builds on [Three-Layer Architecture](../three-layer-architecture/index.md),
[Stateless OOP and dependency injection](../stateless-oop-di/index.md),
[Service-tree identity](../service-tree/index.md) and
[Data validation](../validation/index.md).

---

## Canonical block

One shape for every language, nested the way .NET options bind: booleans per
exporter, no exporter enum strings, the same exporter sub-block on every signal.
Signal keys are exactly `logs`, `metrics` and `traces`.

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

The base block turns the signal pipelines on but keeps every exporter **off**. A
landscape overlay switches on the exporter it needs and sets the endpoint; the base
file never carries a real endpoint. An app ships dark and a landscape lights it up
without a new release.

### Rules the schema enforces

- Signal keys are exactly `logs`, `metrics` and `traces`, case-sensitive.
- Each exporter has its own `enabled` boolean. There is no `use` or `exporterType` enum.
- OTLP is **http/protobuf on port 4318** everywhere. An endpoint on any other port is
  rejected, even on a disabled exporter.
- An **enabled** OTLP exporter with an empty `endpoint` fails validation before startup.
- Durations are ISO 8601 strings (`PT10S`, `PT60S`), parsed with `parseWireDuration`
  from `@atomicloud/diene.core-utils`. They must be positive and fixed-length.
- `traces.sampler.type` is one of `parentbased_traceidratio`, `always_on`, `always_off`;
  `ratio` is finite and within `[0, 1]`.

The package exports `otelBlockSchema`, the sub-schemas, the inferred types
(`OtelBlock`, `OtelTraces`, …) and `defaultOtelBlock`. It validates its own block only;
`@atomicloud/diene.config` loads, merges and validates the composed root schema.

```ts
import { otelBlockSchema } from '@atomicloud/diene.otel';
import { z } from 'zod';

const rootSchema = z.object({ app: appSchema, otel: otelBlockSchema });
```

---

## Resource identity

Resource attributes come from the validated `app:` service-tree values; consumers
never write them by hand. The mapping is fixed:

| Service-tree value | Semantic convention           |
| ------------------ | ----------------------------- |
| landscape          | `deployment.environment.name` |
| platform           | `service.namespace`           |
| service            | `service.name`                |
| version            | `service.version`             |

All five raw values are also set as `atomi.landscape`, `atomi.platform`,
`atomi.service`, `atomi.module` and `atomi.version`.
`ResourceIdentityMapper` builds them; `OTEL_RESOURCE_ATTRIBUTES` and then
`OTEL_SERVICE_NAME` are layered on top.

---

## Standard `OTEL_*` variables win

The library sets an SDK option only when the matching standard variable is unset,
so operators can override the block without a release.

- `OTEL_SDK_DISABLED=true` makes init a no-op: no pipeline is built and seams are ignored.
- `OTEL_LOGS_EXPORTER`, `OTEL_METRICS_EXPORTER`, `OTEL_TRACES_EXPORTER` (`console`, `otlp`,
  `none`) replace the block's exporter flags for that signal.
- `OTEL_TRACES_SAMPLER` set: no programmatic sampler; the SDK reads it.
- `OTEL_EXPORTER_OTLP_[SIGNAL_]ENDPOINT`, `_HEADERS`, `_TIMEOUT` set: the matching option
  is left to the SDK.
- `OTEL_METRIC_EXPORT_INTERVAL` / `OTEL_METRIC_EXPORT_TIMEOUT` (positive milliseconds)
  replace `metrics.interval` and the OTLP timeout for the metric reader.

---

## Design

The package follows three layers:

- **Domain** (`src/lib`, pure): the schemas, `OtelEnvironment` (a read-only view of the
  variables passed in), `ExporterSelector`, `ResourceIdentityMapper`,
  `TraceSamplerFactory`, `OtlpExporterOptionsFactory`, `WireDurationConverter`, the trace
  seam (`TraceEmitter`, `TraceRecordValidator`, `TraceError`) and `OtelPlanner`, which
  turns a block, an identity and the variables into one `OtelPlan`. The domain never
  reads `process.env`.
- **Adapters** (`src/adapters`, effects): `OtelBootstrap` reads the variables
  (`process.env` unless you pass `environment`), asks the planner for a plan and builds
  only what the plan selects through `LoggerSignalFactory`, `MetricSignalFactory` and
  `TraceSignalFactory`.
- **Test helper** (`src/test-helper`): the trace double, assertions, fixtures and the
  init harness.

Every class is stateless and takes its collaborators in the constructor, with working
defaults. Swap one to change behaviour, for example a `MetricSignalFactory` built with
your own `MetricExporterFactories`.

---

## Signal lifecycle

`new OtelBootstrap().init(block, identity, options?)` returns one `OtelRuntime`:

- `tracer`, `meter`, `logger` scoped to the service name and version;
- `traceEmitter`, `metricsCollector`, `loggerSink` (the seam implementations);
- `resource`, `resourceAttributes`, `active` (which signals built a pipeline);
- `flush()` and `shutdown()`.

Call init once and keep the runtime. The library registers **no** process signal
handlers: your framework owns `SIGTERM` and calls `shutdown()`, which flushes every
signal, shuts the providers down and throws one `AggregateError` naming every failure.

When a signal has no selected exporter, its accessors are no-ops and no provider,
exporter, reader, processor, timer or network client is created.

- **Traces**: a node tracer provider with the resource, the mapped sampler and one batch
  span processor per exporter (OTLP proto, console). `parentbased_traceidratio` maps to
  `ParentBasedSampler({ root: TraceIdRatioBasedSampler(ratio) })`; `always_on` and
  `always_off` use their native samplers.
- **Metrics**: a meter provider with one periodic reader per exporter (OTLP proto,
  console), exporting every `metrics.interval`.
- **Logs**: pino JSON to stdout, collected by the platform log agent, with `trace_id`,
  `span_id` and `trace_flags` from the active span. Logs need the console exporter on.
  The OTLP logs bridge is **stubbed** (`runtime.otlpLogsBridge === 'stubbed'`) until the
  JS logs SDK is stable; the package does not depend on `@opentelemetry/sdk-logs`.

---

## Seams

`@atomicloud/diene.interfaces` owns the `LoggerSink` and `MetricsCollector` seams. This
package implements them (`PinoLoggerSink`, `SdkMetricsCollector`); both run the shared
validators first, so a real adapter rejects exactly what the shared mock rejects.

The interfaces package has no trace seam, so `TraceEmitter` and its double live here.

Pass seams to init to replace a signal for a test or a custom sink:

```ts
runtime = new OtelBootstrap().init(block, identity, { seams: { logger, metrics, traces } });
```

A seam is chosen before anything is built, so that signal gets no provider, exporter or
pino output even when its OTLP exporter is on.

---

## Testing

- **Unit** (`src/lib`, 100%): the accept/reject block table, the resource mapping, the
  sampler mapping, the variable rules and the planner. No SDK pipeline runs.
- **Integration** (`src/adapters`, 100%): adapters run in-process with in-memory SDK
  exporters and the shared mocks injected. **No collector and no network.**
- **Meta** (`src/test-helper`, 100%): every assertion is shown to fail on bad input and
  pass on good; the SDK-backed seams and the in-memory doubles give the same outcomes on
  one shared scenario list; the fixtures pass the schema.
- **SIT** (`tests/sit`): real OTLP http/protobuf export of a span and a metric to a
  loopback receiver started by the test on `127.0.0.1`. The receiver decodes the
  protobuf body and checks `service.name`, `deployment.environment.name`, the `atomi.*`
  attributes and the emitted span and metric. The block keeps port 4318; the test
  points the exporters at the receiver through `OTEL_EXPORTER_OTLP_ENDPOINT`. The receiver
  is test-only and never ships.

### Test helper

`@atomicloud/diene.otel/test-helper` ships:

- `InMemoryTraceEmitter`: records validated trace records and calls, with `failNext`.
- `OtelAssertions`: `traceRecords`, `traceCalls`, `resourceAttributes`,
  `identityResource` and `payload`, each throwing `OtelAssertionError` with both sides.
- `OtelBlockFixtures`: `canonical()`, `disabled()`, `console()`, `otlp()` blocks.
- `AppIdentityBuilder`: a valid identity, `with(...)` overrides and the mapped `attributes()`.
- `OtelTestHarness`: `start(block?, identity?, environment?)` inits the runtime with the
  shared logger and metrics mocks and the trace double injected.

The logger and metrics mocks (`InMemoryLoggerSink`, `InMemoryMetricsCollector`) and their
assertions come **only** from `@atomicloud/diene.interfaces/test-helper`; import them from
there. This package does not re-export them.
