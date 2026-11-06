# Faro for Frontends

Next.js and Flutter frontends send telemetry with Grafana Faro, Grafana's frontend observability SDK, instead of an OTel library. Each frontend keeps a thin module of its own around the official Faro SDK: one part starts Faro, one part reports errors, plus its tests.

## Start-up rules

Both frontends must:

1. Read a validated config: an enabled flag, the collector address, the sampling policy and the service-tree `app:` block.
2. Start Faro exactly once, after the client-safe config is available.
3. Do nothing, and make no network calls, when disabled.
4. Fail visibly when enabled with invalid config. Never swallow a start-up failure and pretend telemetry works.
5. Attach the full LPSM and version identity (terms: [Observability Standards](docs/standards/observability/index.md#terms)) to every event, error, session and span.
6. Send unexpected exceptions and expected app errors through the same reporter, after the UI error boundary has shown them. Expected errors are RFC 9457 Problems, as in [Wire format](docs/standards/wire-format/index.md).
7. Redact secrets; send only user and context attributes from an explicit allowlist.
8. Flush on the platform's lifecycle hook where the SDK supports it.

## Identity

| Service-tree value | Faro field / attribute                          |
| ------------------ | ----------------------------------------------- |
| service            | app name / `service.name`                       |
| platform           | app namespace / `service.namespace`             |
| version            | app version / `service.version`                 |
| landscape          | app environment + `deployment.environment.name` |
| module             | `atomi.module` session attribute                |

Also attach `atomi.landscape`, `atomi.platform`, `atomi.service`, `atomi.module` and `atomi.version`. Never take identity from the browser hostname, the Flutter bundle id or user input.

## Next.js

```text
src/lib/observability/
├── config.ts                  # adapts the composed client-safe config; loads no files
├── faro.ts                    # builds metadata and instrumentations; start-once init
├── faro-error-reporter.ts     # the app's error reporter
├── FrontendObservability.tsx  # client-only component that calls init once config is injected
└── index.ts                   # exports the public surface only
```

Use the official `@grafana/faro-web-sdk` and `@grafana/faro-web-tracing` packages. The component must not catch and discard SDK failures.

### Source maps

Upload source maps with `@grafana/faro-webpack-plugin` from the webpack hook in `next.config.ts`, during the production build.

- Add the plugin only when Faro and `client.faro.build.enabled` are both true.
- Require the endpoint, app id, stack id and the build secret `ATOMI_CLIENT__FARO__BUILD__KEY` before uploading.
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

Use Grafana's verified-publisher `faro` package. Map `service` to `appName`, `platform` to `namespace`, `version` to `appVersion` and landscape to `appEnv`; put the `atomi.*` values and `deployment.environment.name` in session or resource attributes. Wrap the app once with the SDK bootstrap, and add only the interaction and asset instrumentation widgets you need.

Flutter does not use the webpack source-map plugin. Native symbol upload belongs to the Flutter release pipeline.

## Tests each frontend needs

- Disabled config makes no network calls.
- Init runs exactly once.
- Every event carries the full LPSM metadata.
- Errors reach the reporter.
- Next.js only: the source-map upload guard.
