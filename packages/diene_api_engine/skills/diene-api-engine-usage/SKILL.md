---
name: diene-api-engine-usage
description: Use when calling backends from a Diene Flutter app with package:diene_api_engine (registering backends, per-backend tokens, Result-typed raw or generated-SDK calls, rescue config), or when testing that code with its TestHelper.
---

# diene_api_engine usage

The package doc (`doc/diene_api_engine.md`) is authoritative; read it first.

- Import only `package:diene_api_engine/diene_api_engine.dart`; never `lib/src`.
- Build the engine with `ApiEngine.fromConfig(ApiEngineConfig.fromMap(block),
auth: ..., store: FileRescueStore(dir))`; one `BackendConfig` per backend.
- Give each backend its own `resourceName`; tokens come from `IAuth` per
  backend, never shared.
- Use `backend.call<T>` for raw JSON and `backend.sdk(GeneratedSdk.new)` plus
  `ResultSdk().call` for generated clients. Handle `Ok` / `Err`; do not catch.
- Do not add URL lists, circuit breakers or your own retries; the engine
  retries once and rescue handles hard failures when `rescue.enabled` is true.
- Keep the issuer and allowed host suffixes in baked build config.

## Tests

Import `package:diene_api_engine/test_helper.dart`: `FakeHttpTransport` for
backends, `FakeAuth` for per-backend tokens, response builders and the
`expectOk` / `expectErr` / `expectProblemType` assertions. See `patterns.md`.
