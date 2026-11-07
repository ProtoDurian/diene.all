# OpenTelemetry Configuration

Applies only if this repo has backend code (Bun, .NET or Go). That code comes from a CyanPrint template for its language (CyanPrint is the template generator described in `CLAUDE.md`; it will record its templates in `.cyan_state.yaml`, which this repo does not have yet, once a template has been applied), which also adds its OTel library ("the library" below), its config library and the config files. This repo has none of them yet.

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

The base config turns the three signals on and every exporter off, and keeps every trace (`ratio: 1.0`). Each landscape's config turns on the exporters it needs, e.g. `otel.traces.exporter.otlp: { enabled: true, endpoint: '{otlp-endpoint}' }` (endpoint from the [platform team](/docs/standards/observability/index.md#values-the-platform-team-gives-you)), and lowers `otel.traces.sampler.ratio` when that landscape's trace volume is high (the platform team asks, or its traces cost more than its logs).

Rules:

- The signal keys are exactly `logs`, `metrics` and `traces`.
- Each exporter is switched by its own `enabled` boolean, not by a string such as `exporter: otlp`.
- OTLP (the OpenTelemetry Protocol) is always HTTP/protobuf (port 4318 by default). `protocol` accepts only `http/protobuf`; the libraries reject anything else, so keep the line.
- Durations are ISO 8601 strings: `PT10S` is 10 seconds.
- The sampler `type` is `parentbased_traceidratio` (follow the caller's sampling decision if there is one, else keep the `ratio` share, 0 to 1, of new traces), `always_on` or `always_off`.
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

It also sets `atomi.landscape`, `atomi.platform`, `atomi.service`, `atomi.module` and `atomi.version`. `atomi.*` is the organisation's own attribute namespace: it holds the raw values (including `module`, which has no standard attribute), so queries match the LPSM labels exactly. The collector (run by the platform team) turns the `atomi.*` values into the labels `landscape`, `platform`, `service` and `module` that every query in these docs uses; if a query finds nothing, check one series in Grafana Explore for the label names your collector produces.

## Standard HTTP metrics

HTTP servers report OTel's standard HTTP metric. Exported to Prometheus it is the histogram `http_server_request_duration_seconds`; its `_count` series counts requests. Its labels include `http_response_status_code`, `http_request_method` and `http_route` (the route template, e.g. `/orders`, not the raw path). Check one series in Grafana Explore before you use it.

## Standard `OTEL_*` environment variables win

If a standard `OTEL_*` variable is set (endpoint, headers, resource attributes, propagators, sampler, `OTEL_SDK_DISABLED`), the library uses it instead of the config block. Whoever deploys the service can then change telemetry without a new release.

## Start and shutdown

Start telemetry once at startup. Call the library's flush and shutdown from the service's own shutdown hook (e.g. on `SIGTERM`); the library never installs signal handlers itself.

Per language:

- **Bun**: pino (the Bun template's JSON logger) writes JSON logs to stdout, with the trace context and fixed keys `level` (a number, e.g. `50` = error), `msg` and `time`, and Grafana Alloy (the collector) reads stdout, so leave `otel.logs.exporter.otlp.enabled: false`. Metrics and traces go over OTLP.
- **.NET**: `Microsoft.Extensions.Logging` and the OpenTelemetry hosting integration. Logs go where `otel.logs.exporter` sends them (`console` = stdout, `otlp` = the collector); sample the stored lines and record their keys in `observability/dashboards/log-notes.md`.
- **Go**: `slog` and the OpenTelemetry Go SDK. Logs and their keys: as for .NET.

## Testing

- **Unit tests**: every landscape's config passes validation.
- **Integration tests**: test with the in-memory exporter the language template's OTel library ships; never start a fake collector.
- **Real export**: checked after deploy, in Grafana Explore.
