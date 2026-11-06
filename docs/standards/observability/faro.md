# Faro for Frontends

Applies only if this repo is a Next.js or Flutter frontend; otherwise skip this page.

Frontends send telemetry with Grafana Faro, Grafana's frontend observability SDK, instead of an OTel library. Each frontend keeps a thin module of its own around the official Faro SDK: one part starts Faro, one part reports errors, plus its tests.

## Start-up rules

Both frontends must:

1. Read a validated config under `client.faro`: an enabled flag, the Faro collector URL, the sampling ratio, the app id (this frontend's app in Faro) and the stack id (the Grafana stack that holds it), plus the service-tree `app:` block (shape in [OpenTelemetry](/docs/standards/observability/otel.md#resource-attributes)). Key names other than `client.faro.build.*` come from the frontend template's config schema. The collector URL, app id and stack id come from the [platform team](/docs/standards/observability/index.md#values-the-platform-team-gives-you).
2. Start Faro exactly once. How the client config (the part of the app config that may reach the browser) reaches the browser is the frontend template's job; init runs once that config is readable.
3. Do nothing, and make no network calls, when disabled.
4. Fail visibly when enabled with invalid config. Never swallow a start-up failure and pretend telemetry works.
5. Attach the full LPSM and version identity to every event, error, session and span (table below).
6. Send unexpected exceptions and expected app errors through the same reporter, after the UI error boundary has shown them. Expected errors are RFC 9457 Problems, as in [Wire format](/docs/standards/wire-format/index.md).
7. Redact secrets; send user and context attributes only from an explicit allowlist, e.g. `user.id` yes, `user.email` no.
8. Flush when the page is hidden or the app is paused, where the SDK supports it.

## Identity

| Service-tree value | Faro field / attribute                          |
| ------------------ | ----------------------------------------------- |
| service            | app name / `service.name`                       |
| platform           | app namespace / `service.namespace`             |
| version            | app version / `service.version`                 |
| landscape          | app environment + `deployment.environment.name` |
| module             | `atomi.module` session attribute                |

Also attach the `atomi.*` values ([why](/docs/standards/observability/otel.md#resource-attributes)). Never take identity from the browser hostname, the Flutter bundle id or user input.

## Next.js

```text
src/lib/observability/
├── config.ts                  # adapts the client config; loads no files
├── faro.ts                    # builds metadata and instrumentations; start-once init
├── faro-error-reporter.ts     # the app's error reporter
├── FrontendObservability.tsx  # client-only component that calls init once the client config is readable
└── index.ts                   # exports the public surface only
```

Use the official `@grafana/faro-web-sdk` and `@grafana/faro-web-tracing` packages. The component must not catch and discard SDK failures.

### Source maps

Upload source maps with `@grafana/faro-webpack-plugin` from the webpack hook in `next.config.ts`, during the production build.

- Add the plugin only when Faro and the app config's `client.faro.build.enabled` are both true.
- Require the collector URL, app id, stack id and the build secret `ATOMI_CLIENT__FARO__BUILD__KEY` before uploading. The name is the app's prefix `ATOMI_` plus the config path `client.faro.build.key` in upper case, with `__` between levels.
- Read the key from the build environment just before the build. It must never reach YAML, the generated client config, `DefinePlugin` values, the bundle, the image or any build output.
- Test the upload guard in CI with a dry run.

## Flutter

```text
lib/src/observability/
├── faro_config.dart
├── faro_bootstrap.dart
├── faro_error_reporter.dart
└── observability.dart
```

Use the `faro` package on pub.dev, published by Grafana (verified publisher). Map `service` to `appName`, `platform` to `namespace`, `version` to `appVersion` and landscape to `appEnv`; put the `atomi.*` values and `deployment.environment.name` in session or resource attributes. Wrap the app once with the SDK bootstrap, and add only the interaction and asset instrumentation widgets you need.

Flutter does not use the webpack source-map plugin; native symbol upload is not covered here.

## Tests each frontend needs

- Disabled config makes no network calls.
- Init runs exactly once.
- Every event carries the full LPSM metadata.
- Errors reach the reporter.
- Next.js only: the source-map upload guard.
