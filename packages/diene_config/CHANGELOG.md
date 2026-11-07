# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## Unreleased (0.0.0)

No public symbol or signature change from 1.0.0. One public constant changes
value:

- `c0ConfigContract.provenance.c0Sections` is now `['Config precedence']` (was
  a section reference into an internal document). No digest covers it.

Other changes:

- The repository, homepage and issue tracker move to
  `ProtoDurian/diene.dart_config`.
- API doc comments are shorter; the package doc moves to
  `doc/diene_config.md`.
- Conformance tests check pinned copies of the shared config cases and local
  fixtures, instead of a generated projection.
- Unit tests read real YAML layer files from disk.

## 1.0.0

- Add the layered loader: full base YAML, then a sparse flavor or landscape
  overlay, then an optional development override, then enumerated
  `--dart-define` values last. The service-composed schema validates only the
  final merged tree, once.
- Add `YamlConfigSource`, which reads a layer through an injected text
  callback, so the package imports neither `dart:io` nor Flutter.
- Add `ConfigBlock<T>`, `ConfigBlockSchema` and `ConfigSchema`: each engine
  exports its own block and the service composes them.
- Add the immutable `DieneConfig` with `slice`, `hasSlice`, `optionalSlice`,
  `rawSlice`, an unmodifiable `raw` tree and `stableProjection`.
- Add `landscape()` over the build-time `DIENE_LANDSCAPE` define, with
  `DartDefineLandscapeSource`. Nothing is detected; a blank value is missing.
- Report expected failures as `Result` values holding a `Problem`:
  `ConfigProblemCode`, `configProblem`, `configFailure` and
  `configProblemCode`. `schema_invalid` lists every error found.
- Return the `diene_core_utils` problem unchanged for a bad define key.
- Use the `diene_core_utils` merge and define helpers instead of a private
  copy. Lists come only from indexed keys (`FOO__0`, `FOO__1`); JSON and comma
  values are never decoded; blank values are unset; keys match ignoring case,
  `-` and `_`, and the base spelling wins.
- Export the pinned shared config contract identity from `c0_config.dart`.
- Add `test_helper.dart`: `FakeConfigSource`, `FailingConfigSource`,
  `FakeLandscapeSource`, `ConfigStubBuilder`, `FakeConfigHarness`,
  `expectOkConfig`, `expectErrConfig`, `assertConfigProblem` and
  `assertConfigSlice`, with no test-framework import.
- Add `config/app_config.dart` with `AppConfig`, so an app moving off an
  in-app `AppConfig` changes one import.
