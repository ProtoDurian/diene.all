# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## Unreleased (0.0.0)

Every 1.0.0 name and signature is unchanged.

Fixed:

- `parseAppHandoffInstallReferrer` threw an `ArgumentError` on a malformed
  percent escape (for example `app_handoff=%zz`), although it promises `null`
  for an invalid referrer. It now returns `null` for a bad `app_handoff` value
  and ignores a field whose name does not decode. So
  `DeferredLoginJourney.redeemCarrier` falls back to interactive login instead
  of throwing.

Changed:

- `isValidAppHandoffNonce`, `buildAppHandoffCarrier` and
  `parseAppHandoffCarrier` now use `diene_auth_engine`'s `AppHandoffCarrier`,
  so the carrier format has one implementation. Their results are the same as
  in 1.0.0.
- The harness code now lives in `lib/test_helper.dart` itself, not in
  `lib/src/assertions/`, `lib/src/journey/` and `lib/src/stub/`. The import
  `package:diene_e2e/test_helper.dart` and every name are unchanged.
- The repository, homepage and issue tracker now point at
  `https://github.com/ProtoDurian/diene.dart_e2e`.
- The README, package doc and usage skill now describe this package, including
  the differences from the Bun harness and the known limits of 1.0. The usage
  skill's `patterns.md` was the library template's and is removed.
- The conformance tests now check the shared app-handoff and problem-member
  vectors directly.

## 1.0.0

- First release: the family runtime re-exports, the six member TestHelper
  passthroughs, `StubServer`, `Journey`, the app-handoff carrier codec and wire
  models, `AppHandoffStub`, `DeferredLoginJourney` and plain-throw assertions.
