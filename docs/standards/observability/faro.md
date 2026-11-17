# Faro for Frontends

Applies only if this repo is a Next.js or Flutter frontend; otherwise skip this page.

Frontends send telemetry with Grafana Faro, Grafana's frontend observability SDK, instead of an OTel library. Each frontend keeps a thin module of its own around the official Faro SDK: one part starts Faro, one part reports errors, plus its tests.

## Start-up rules

Both frontends must:

1. Read a validated config under `client.faro`: an enabled flag, the Faro collector URL, the sampling ratio, the app id (this frontend's app in Faro) and the stack id (the Grafana stack that holds it), plus the service-tree `app:` block (shape in [Identity](#identity)). Key names other than `client.faro.build.*` come from the frontend template's config schema. The collector URL, app id and stack id come from the [platform team](/docs/standards/observability/index.md#values-the-platform-team-gives-you).
2. Start Faro exactly once. How the client config (the part of the app config that may reach the browser) reaches the browser is the frontend template's job; init runs once that config is readable.
3. Do nothing, and make no network calls, when disabled.
4. Fail visibly when enabled with invalid config. Never swallow a start-up failure and pretend telemetry works.
5. Attach the full LPSM and version identity to every event, error, session and span (table below).
6. Send unexpected exceptions and expected app errors through the same reporter, after the UI error boundary (the component that catches render errors and shows a fallback; in Flutter, `FlutterError.onError`/`ErrorWidget`) has shown them. Expected errors are RFC 9457 Problems, as in [Wire format](/docs/standards/wire-format/index.md).
7. Redact secrets; send user and context attributes only from an explicit allowlist, e.g. `user.id` yes, `user.email` no.
8. Flush when the page is hidden or the app is paused, where the SDK supports it.

## Identity

Phones and browsers have no pod, so the build sets the identity (never the pod labels that Alloy reads for backends).

| Service-tree value | Faro field / attribute                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------- |
| service            | app name (`app.name`) / `service.name`                                                    |
| platform           | app namespace (`app.namespace`) / `service.namespace`                                     |
| version            | app version / `service.version`                                                           |
| module             | `durian.cloud.module` on every log, event and span                                        |
| landscape          | never sent by the client: the landscape's `faro.receiver` stamps `durian.cloud.landscape` |

The tracer resource also sets `service.namespace` to the platform, because Faro traces carry no `app.namespace`. The client is not trusted: never take identity from the browser hostname, the Flutter bundle id or user input.

## The edge in front of Alloy

Phones and browsers send to an **edge service**, one small service of the sulfoxide platform in every serving cluster, in front of each landscape's Grafana Alloy `faro.receiver`. It has a per-address rate limit only. A phone sends to `faro.edge.sulfoxide.<landscape>.cluster.durian.cloud` and, after login, to its home landscape, so one landscape holds a phone's whole session. The edge does four things before the payload reaches Alloy:

1. **Client country.** It decides the country once (`CF-IPCountry` when Cloudflare is in front, else an offline country lookup, else `unknown`), writes the log field `session_attr_country` and the span attribute `client.country`, and **deletes every address header**. The client address is never stored. Country is a log field, never a stream field.
2. **Stack decode.** For each exception whose stack has `build_id` and `virt` frames, it decodes the stack with `llvm-symbolizer` and the build's symbols and replaces the frames with readable ones. An unknown build id keeps the raw stack with `error.symbolicated=false`.
3. **Error group.** It sets `error.group` (a hash of the error type and the top in-app frames, without line numbers), `error.top` and `error.symbolicated`, so the same bug from two releases lands in one group.
4. **Result errors** keep the stack of where the failure was created and carry `error.chain`, `error.step` and `error.step_name`.

`faro.receiver` sets `rate_limiting` on purpose (its default is one global bucket for all phones together). Keep markers for cross-cluster tail sampling go to the per-cluster edge names ([keep markers](/docs/standards/observability/otel.md#cross-cluster-tail-sampling-keep-markers)).

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

Use the `faro` package on pub.dev, published by Grafana (verified publisher). Map `service` to `appName`, `platform` to `namespace`, `version` to `appVersion` and landscape to `appEnv`; put `durian.cloud.module` in the session or resource attributes. Wrap the app once with the SDK bootstrap, and add only the interaction and asset instrumentation widgets you need.

Flutter does not use the webpack source-map plugin; native symbol upload is not covered here.

## Tests each frontend needs

- Disabled config makes no network calls.
- Init runs exactly once.
- Every event carries the full LPSM metadata.
- Errors reach the reporter.
- Next.js only: the source-map upload guard.
