# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## Unreleased (0.0.0)

The public API and behaviour of 1.0.2 are unchanged. Every 1.0.2 symbol keeps
its name and signature.

Added:

- `FakeRedeemHttpClient` in `package:diene_auth_engine/test_helper.dart`: an
  HTTP stub that answers only `POST {mount}/redeem`. Any other path, including a
  doubled `app-handoff` segment, gets 404, and a malformed body gets 400.

Changed:

- The TestHelper code now lives in `lib/test_helper.dart` itself, not in
  `lib/src/test_helper/`. The import `package:diene_auth_engine/test_helper.dart`
  is unchanged.
- The repository, homepage and issue tracker now point at
  `https://github.com/ProtoDurian/diene.dart_auth_engine`.
- The docs say plainly that Doc B is fetched whenever the home claim is absent,
  on sign-in or sign-up. The code already behaved this way.
- The conformance tests now check the shared identity vectors directly.

## 1.0.2

- Ship `lib/src/config/`, which 1.0.0 and 1.0.1 left out of the archive.

## 1.0.1

- Format the released changelog.

## 1.0.0

- First release: Logto sign-in, per-resource tokens, per-backend claims-first
  onboarding, deferred login, returnTo continuation, Doc B home selection, the
  `authEngine` config block schema and the TestHelper.
