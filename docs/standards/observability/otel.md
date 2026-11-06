# OpenTelemetry Configuration

Backend services send logs, metrics and traces with OpenTelemetry (OTel). Bun, .NET and Go each have their own OTel library, but all three read the same `otel:` config block, set the same resource attributes and start and stop the same way. Frontends use Grafana Faro instead; see [Faro](docs/standards/observability/faro.md).

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

The base config turns the three signals on and every exporter off. Each landscape's config file turns on the exporter it needs and sets its endpoint.

Rules:

- The signal keys are exactly `logs`, `metrics` and `traces`.
- Each exporter is switched by its own `enabled` boolean, not by a string such as `exporter: otlp`.
- OTLP always uses HTTP/protobuf on port 4318.
- Durations are ISO 8601 strings: `PT10S` is 10 seconds.
- The sampler `type` is `parentbased_traceidratio`, `always_on` or `always_off`; `ratio` is between 0 and 1.
- A disabled exporter creates no network client and no background worker.
- An enabled exporter with an empty `endpoint` fails config validation before startup.

## Who owns what

| Part                                                     | Owner                                        |
| -------------------------------------------------------- | -------------------------------------------- |
| The `otel:` block's types and schema                     | The language's OTel library                  |
| Loading YAML and env vars, merge order, final validation | The language's config library                |
| Database, cache and storage presets                      | The config library (never the `otel:` block) |
| The logging and metrics interfaces the code calls        | The language's common interfaces library     |
| The real SDK behind those interfaces                     | The language's OTel library                  |
| Calling start and shutdown, and testing real export      | This service                                 |

The service adds the OTel schema to its root config schema in one line, without copying or wrapping it.

## Resource attributes

The library builds these from the validated `app:` block (the service-tree values). Never set them by hand.

| `app:` value | OTel attribute                |
| ------------ | ----------------------------- |
| landscape    | `deployment.environment.name` |
| platform     | `service.namespace`           |
| service      | `service.name`                |
| version      | `service.version`             |

It also sets the raw values as `atomi.landscape`, `atomi.platform`, `atomi.service`, `atomi.module` and `atomi.version`.

## Standard `OTEL_*` environment variables win

If a standard `OTEL_*` variable is set (endpoint, headers, resource attributes, propagators, sampler, `OTEL_SDK_DISABLED`), the library uses it instead of the config block. Operators can then change telemetry without a new release.

## Start and shutdown

Every library:

1. validates the `otel:` block;
2. builds the resource attributes from `app:`;
3. starts each enabled signal exactly once;
4. gives the service a logger, meter and tracer;
5. offers an explicit flush and shutdown;
6. never registers process signal handlers. The service calls flush and shutdown from its own shutdown hook.

Per language:

- **Bun**: pino for logs, with the trace context added, written as JSON to stdout. Grafana Alloy (the collector agent on each node) reads stdout. Metrics and traces go over OTLP. Sending logs over OTLP is not implemented yet.
- **.NET**: `Microsoft.Extensions.Logging` and the OpenTelemetry hosting integration.
- **Go**: `slog` and the OpenTelemetry Go SDK.

## Testing

- **Unit tests**: the schema accepts and rejects the right configs; resource and sampler mapping; disabled exporters create nothing.
- **Integration tests**: use the libraries' in-memory telemetry; never start a fake collector.
- **Real export**: tested end to end by the deployed service through the real collector.
