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

The library builds `service.version` from the `app:` block of the config. It sets none of the where-from keys and not `service.name`: [Alloy sets those from the pod labels](#where-from-keys). Never set them by hand.

```yaml
app:
  version: 1.4.0
```

| `app:` value | OTel attribute    |
| ------------ | ----------------- |
| version      | `service.version` |

## Where-from keys

Every signal says where it came from: landscape, platform, service and module. **The app does not set these and the libraries never set `service.name`.** Grafana Alloy reads them from the pod's labels `durian.cloud/<key>` (`otelcol.processor.k8sattributes`; `pyroscope.enrich` for pushed profiles) and writes them on every signal as `durian.cloud.landscape`, `durian.cloud.platform`, `durian.cloud.service` and `durian.cloud.module`. Alloy also copies service, platform and landscape into `service.name`, `service.namespace` and `deployment.environment.name`, and the pod label wins over anything the app sent.

The library's only duty is to pass the pod's own identity from the environment: the service chart template passes `k8s.pod.uid`, `k8s.pod.name` and `k8s.container.name` through the downward API into `OTEL_RESOURCE_ATTRIBUTES`, and the library reads that standard variable. Alloy matches a signal to its pod by `k8s.pod.uid` first. Profiles carry `pod=<POD_NAME>`; the library reads `POD_NAME` (set from the downward API).

How each store spells the keys:

| Store           | Spelling                                    | Query example                                                           |
| --------------- | ------------------------------------------- | ----------------------------------------------------------------------- |
| VictoriaLogs    | dots kept, quoted                           | `_stream:{"durian.cloud.landscape"="pichu", "service.name"="checkout"}` |
| VictoriaMetrics | dots kept, quoted                           | `{"durian.cloud.service"="checkout"}`                                   |
| Tempo           | dots, as sent                               | `{resource.durian.cloud.landscape="pichu"}`                             |
| Pyroscope       | underscores only (dotted names are dropped) | `{durian_cloud_service="checkout", service_name="checkout"}`            |

Frontends have no pod: see [Faro](/docs/standards/observability/faro.md#identity).

## Labels are bounded sets

Each service declares its signals in one **contract file**; a code generator turns it into types, so app code can only send what the contract declares. A metric label or a VictoriaLogs stream field is one of:

- an **enum** (listed values, e.g. `provider: [stripe, adyen, paypal]`);
- a **bounded number** (`min..max`, e.g. `shard: 0..15`);
- a **time bucket** (`hour_of_day` 0..23 or `weekday` 0..6).

`free` (any value) is allowed only on log fields and span attributes. A user id is a normal log field and span attribute; it has no type that fits a metric label or a stream field, so it can never become one. A calendar date may be a metric label only when the contract states how many values are live at once (`window_days`), and is never a stream field.

Each metric keeps a `budget:`. The obs check computes the worst-case series count from the contract (the product of the label sizes; times 14 for a 12-bucket histogram) and fails when it is over budget, on `free` in a metric label or stream field, on a calendar date without `window_days`, and on a gauge with neither `across_pods` nor `per_pod`. `obs check` is the check that enforces the contract; see [Checks with `obs`](#checks-with-obs).

## VictoriaLogs stream fields

Logs are stored in VictoriaLogs and queried with LogsQL. Its stream fields are only the bounded where-from set, exactly these eight:

`VL-Stream-Fields: service.name, service.namespace, deployment.environment.name, k8s.namespace.name, durian.cloud.landscape, durian.cloud.platform, durian.cloud.service, durian.cloud.module`

Alloy's OTLP log exporter sends them in the `VL-Stream-Fields` header. Without the header VictoriaLogs makes every resource attribute a stream field (one stream per pod) and adds `event_name` too. Every other field (`user_id`, `trace_id`, pod, container and node ids, the stack trace, the event name) is an ordinary field: it stays filterable but is never a stream field. Field names are the OTLP names as sent, dots and slashes kept, and a dotted name is quoted in LogsQL: `_stream:{"durian.cloud.service"="cart"} "durian.cloud/event":=checkout.failed`. Severity is `severity_text` and `severity_number`, the body is `_msg`, and trace ids are `trace_id` and `span_id`; there is no `level` field.

## Cross-cluster tail sampling: keep markers

Alloy samples traces after they end, per cluster. A request can cross clusters, and each cluster's sampler sees only its own spans, so every cluster that handles a piece of a trace must keep its piece when any other piece is kept.

- The keep rule: a 5 % roll on the trace id with a shared salt (every cluster rolls the same number for the same trace), any trace with an error, any trace slower than 500 ms and any trace with the span attribute `durian.keep = "true"`.
- **Keep markers.** When a cluster's router sees an error span, a span over 500 ms or a `durian.keep` span, it sends a small marker span for that trace id to every sibling cluster. The sibling's sampler treats the marker as `durian.keep = "true"` and keeps its own spans for that trace. Marker spans are named `durian.keep-marker` and are dropped after the sampler, so they never reach Tempo. There is no ring between clusters and no answer header.
- The decision wait is 15 seconds (`traces.tail.decision_wait`), long enough for a marker to arrive.
- Queue jobs start a new trace with a span link to the producer and copy the producer's trace id into `durian.link.trace_id`.
- The sibling list is the Argo CD cluster Secret annotation `durian.cloud/siblings`, which reaches the Alloy chart value `markers.siblings`. A multi-cluster landscape that renders zero marker exporters is an error.

## Checks with `obs`

`obs` is one command-line tool, in the dev shell, that checks the contract, alerts, dashboard queries and links in CI with the stores' own engines inside it, with no running stack. `obs --help` prints its commands. This repo does not run `obs check` or `obs gen` in CI yet.

## Versions

One version set is used everywhere; the stores in the charts, the sandbox and `obs` use the same versions, and one bump moves them together.

| Piece                                                               | Version  |
| ------------------------------------------------------------------- | -------- |
| Grafana Alloy                                                       | v1.21.3  |
| VictoriaLogs                                                        | v1.54.0  |
| Tempo                                                               | 3.1.1    |
| Pyroscope                                                           | 2.4.3    |
| VictoriaMetrics                                                     | v1.156.0 |
| Grafana (alert rules, dashboards)                                   | 13.3.0   |
| Grafana VictoriaLogs datasource (`victoriametrics-logs-datasource`) | v0.34.0  |

The Loki-API proxy exists only so Grafana Explore works with VictoriaLogs; VictoriaLogs replaced Loki as the log store.

## Standard HTTP metrics

HTTP servers report OTel's standard HTTP metric. Exported to Prometheus it is the histogram `http_server_request_duration_seconds`; its `_count` series counts requests. Its labels include `http_response_status_code`, `http_request_method` and `http_route` (the route template, e.g. `/orders`, not the raw path). Check one series in Grafana Explore before you use it.

## Standard `OTEL_*` environment variables win

If a standard `OTEL_*` variable is set (endpoint, headers, resource attributes, propagators, sampler, `OTEL_SDK_DISABLED`), the library uses it instead of the config block. Whoever deploys the service can then change telemetry without a new release.

## Start and shutdown

Start telemetry once at startup. Call the library's flush and shutdown from the service's own shutdown hook (e.g. on `SIGTERM`); the library never installs signal handlers itself.

Per language:

- **Bun**: logs, metrics and traces all go over OTLP. A JSON logger (pino in the Bun template) writes the trace context into each line; leave `otel.logs.exporter.console.enabled: false` outside local runs.
- **.NET**: `Microsoft.Extensions.Logging` and the OpenTelemetry hosting integration. Logs go where `otel.logs.exporter` sends them (`console` = stdout, `otlp` = the collector); sample the stored lines and record their keys in `observability/dashboards/log-notes.md`.
- **Go**: `slog` and the OpenTelemetry Go SDK. Logs and their keys: as for .NET.

## Testing

- **Unit tests**: every landscape's config passes validation.
- **Integration tests**: test with the in-memory exporter the language template's OTel library ships; never start a fake collector.
- **Real export**: checked after deploy, in Grafana Explore.
