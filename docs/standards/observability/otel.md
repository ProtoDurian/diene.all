# OpenTelemetry Configuration

Applies only if this repo has backend code (Bun, .NET or Go). The language template that adds the code also adds its OTel library, its config library and the config files; this repo has none of them yet.

Backend services send logs, metrics and traces with OpenTelemetry (OTel). All three languages read the same `otel:` config block and set the same resource attributes. Frontends use Grafana Faro instead; see [Faro](/docs/standards/observability/faro.md).

## The config block

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
        headers: {}
        timeout: PT10S
```

The base config turns the three signals on and every exporter off. Each landscape's config turns on the exporters it needs, e.g. `otel.traces.exporter.otlp: { enabled: true, endpoint: '{otlp-endpoint}' }` (endpoint from the [platform team](/docs/standards/observability/index.md#values-the-platform-team-gives-you)).

Rules:

- The signal keys are exactly `logs`, `metrics` and `traces`.
- Each exporter is switched by its own `enabled` boolean, not by a string such as `exporter: otlp`.
- OTLP is always HTTP/protobuf (port 4318 by default); there is no protocol setting.
- Durations are ISO 8601 strings: `PT10S` is 10 seconds.
- The sampler `type` is `parentbased_traceidratio`, `always_on` or `always_off`; `ratio` (0 to 1) is the share of new traces kept.
- An enabled exporter with an empty `endpoint` fails config validation before startup.

## Resource attributes

The library builds these from the `app:` block of the config. Never set them by hand.

```yaml
app:
  landscape: raichu
  platform: tracker
  service: zinc
  module: webhook
  version: 1.4.0
```

| `app:` value | OTel attribute                |
| ------------ | ----------------------------- |
| landscape    | `deployment.environment.name` |
| platform     | `service.namespace`           |
| service      | `service.name`                |
| version      | `service.version`             |

It also sets `atomi.landscape`, `atomi.platform`, `atomi.service`, `atomi.module` and `atomi.version`. `atomi.*` is the organisation's own attribute namespace: it holds the raw values (including `module`, which has no standard attribute), so queries match the LPSM labels exactly.

## Standard `OTEL_*` environment variables win

If a standard `OTEL_*` variable is set (endpoint, headers, resource attributes, propagators, sampler, `OTEL_SDK_DISABLED`), the library uses it instead of the config block. Operators can then change telemetry without a new release.

## Start and shutdown

Start telemetry once at startup. Call the library's flush and shutdown from the service's own shutdown hook (e.g. on `SIGTERM`); the library never installs signal handlers itself.

Per language:

- **Bun**: pino writes JSON logs, with the trace context, to stdout, and Grafana Alloy (the collector) reads stdout, so leave `otel.logs.exporter.otlp.enabled: false`. Metrics and traces go over OTLP.
- **.NET**: `Microsoft.Extensions.Logging` and the OpenTelemetry hosting integration.
- **Go**: `slog` and the OpenTelemetry Go SDK.

## Testing

- **Unit tests**: every landscape's config passes validation.
- **Integration tests**: use the library's in-memory telemetry; never start a fake collector.
- **Real export**: checked after deploy, in Grafana Explore.
