---
name: diene-auth-engine-usage
description: Use when wiring Logto sign-in, per-resource tokens, per-backend onboarding, deferred login, returnTo or Doc B home selection in a Flutter app with package:diene_auth_engine, or when testing that code with its TestHelper.
---

# diene_auth_engine usage

The package doc (`doc/diene_auth_engine.md`) is authoritative; read it first.

- Import only `package:diene_auth_engine/diene_auth_engine.dart`; never `lib/src`.
- Build `AuthEngineConfig` from the merged `authEngine` block. The issuer is
  build-time config; never take it from a document.
- Get tokens through `IAuth` (`AuthCoordinator`), one per `ResourceKey`.
- Register every backend in a `BackendRegistry` and run
  `MultiBackendOnboarding`. Read each backend's own phase; there is no global
  onboarded flag.
- Gate on JWT claims. Call `markStaleClaim()` for a later 401/404; never re-run
  `/User/Me` yourself.
- Set `appHandoffMount` when the host is not on `/app-handoff`; use
  `config.redeemPath` and never build the redeem path by hand.
- Use `SignInCoordinator` for the full flow so Doc B runs only while the home
  claim is absent.

## Tests

Import `package:diene_auth_engine/test_helper.dart`. It has fakes for every
seam (`FakeAuthProvider`, `FakeAuth`, `FakeUserDirectory`,
`FakeRedeemHttpClient`, …), `AuthFixtures` builders and `AuthExpect`
assertions that throw `AuthAssertionError`. See `patterns.md`.
