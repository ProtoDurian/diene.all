---
name: diene-config-usage
description: Use when consuming package:diene_config — loading layered YAML configuration, composing engine-owned ConfigBlock schemas, reading typed slices or the landscape, handling its Result/Problem failures, or testing with its dependency-light TestHelper.
---

# diene_config usage

The package doc (`doc/diene_config.md`) is authoritative; read it first.
`patterns.md` has short examples.

- Import `package:diene_config/diene_config.dart`; never `lib/src`.
- Layer order is fixed: base YAML, overlay, development override, then
  `--dart-define` values last. Only the final merged tree is validated.
- Never write another engine's block; compose the `ConfigBlock` it exports.
- Keep the composed `ConfigBlock` instances and pass the same ones to `slice`.
- Lists in defines use indexed keys (`ACME_APP__TAGS__0`); JSON or comma values
  are never decoded, and a blank value is unset.
- Pass the landscape in through `--dart-define=DIENE_LANDSCAPE=<track>`; never
  detect it.
- `load()` returns `Result`; handle it with `match` or a `switch`, not
  `try`/`catch`.

## TestHelper

Use `package:diene_config/test_helper.dart` (`FakeConfigSource`,
`FakeConfigHarness`, `ConfigStubBuilder`, `FakeLandscapeSource`,
`expectOkConfig`, `assertConfigProblem`) instead of hand-rolled fakes. It
imports no test framework.
