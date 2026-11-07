# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## Unreleased (0.0.0)

Every 1.0.0 symbol keeps its name. Only the `BridgeProblems` class modifier
changed (see Changed); every other signature is the same.

Fixed (each used to throw where 1.0.0 promised a `Result`):

- `toResult` and `Backend.call`: an error body shaped like a problem that
  `Problem.fromJson` cannot parse (for example a numeric `title`) threw a
  `TypeError`. It is now an unexpected-response `Problem` with the status and
  body kept.
- Rescue: a Doc A without a finite numeric `version` threw (a `TypeError`, or
  an `UnsupportedError` for a huge number such as `1e400`). That host is now
  skipped like any unusable host.
- Rescue: a Doc A host, a baked catalog host or a Doc C candidate that is not a
  valid URL threw a `FormatException`. It is now skipped.
- Rescue: a stored pin or last-known-good that is not a valid URL threw a
  `FormatException`. It is now treated as absent.

Changed:

- `BridgeProblems` is now an `abstract class` with no constructor; before, it
  was a plain class with only a private constructor. Code written for 1.0.0
  still works: it still cannot be created, its static members are unchanged,
  and it can now also be extended.
- The TestHelper code now lives in `lib/test_helper.dart` itself, not in
  `lib/src/test_helper/`. The import `package:diene_api_engine/test_helper.dart`
  and every helper name are unchanged.
- The repository, homepage and issue tracker now point at
  `https://github.com/ProtoDurian/diene.dart_api_engine`.
- The README, package doc and usage skill now describe this package, including
  the rescue steps, the differences from the Bun engine and the known limits.
- The conformance tests now check the shared problem and resource-audience
  vectors directly.

## 1.0.0

- First release: `Result`-typed raw and generated-SDK calls, the N-backend
  client tree with per-backend tokens, retry once on a network failure, the
  dormant rescue router with disk storage, the engine config block schema
  and the TestHelper.
