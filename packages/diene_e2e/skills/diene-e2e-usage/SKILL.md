---
name: diene-e2e-usage
description: Use when writing integration or end-to-end tests for a Diene Flutter app with package:diene_e2e (bundled member TestHelpers, StubServer, Journey, the app-handoff stub and DeferredLoginJourney).
---

# diene_e2e usage

The package doc (`doc/diene_e2e.md`) is authoritative; read it first.

- In tests, import `package:diene_e2e/test_helper.dart`: it carries the result,
  interfaces, problems, config, auth-engine and api-engine TestHelpers. There
  is none for core-utils, OpenTelemetry or standard-config; do not add one.
- `expectOk`/`expectErr` are `diene_result`'s and `FakeAuth` is
  `diene_auth_engine`'s. For the api-engine variants, import
  `package:diene_api_engine/test_helper.dart` with a prefix.
- For member fakes and assertions, follow that member's own skill.
- Point clients at a `StubServer`; write flows as a `Journey`; assert with
  `expectJourneyOk` / `expectJourneyFailedAt`; close the server in tear-down.
- For deferred login, mount `AppHandoffStub` on the server and set
  `mintingUser` before minting. Never write a second app-handoff server.
- Drive it with `DeferredLoginJourney`, or with the auth engine's
  `DeferredLoginClient` and `HttpAppHandoffApi` to test the production client.
- Build carriers with `buildAppHandoffCarrier` /
  `buildAppHandoffInstallReferrer`; do not hand-write them.
