# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## Unreleased (0.0.0)

No public symbol, signature or behaviour change from 1.0.1. Three constant
values change:

- `c0TemporalContract.provenance.c0Section` is now `Serialization` (was a
  section reference into an internal document).
- `c0TemporalContract.provenance.c0Source` is now `C0 contracts` (was an
  internal file path).
- `c0TemporalContract.provenance.contentSha256` is recomputed for those two
  values, because `digestPayload()` includes them. Every test vector is
  unchanged. A consumer that pins `contentSha256` must update it; only the
  first line of `digestPayload()` changes.

Other changes:

- The repository, homepage and issue tracker move to
  `ProtoDurian/diene.dart_core_utils`.
- API doc comments are shorter; the package doc moves to
  `doc/diene_core_utils.md`.
- Conformance tests check pinned copies of the shared config vectors and local
  temporal fixtures, instead of a generated projection.
- The IANA timezone list is generated from the official `tzdata2026b.tar.gz`
  archive, stored unmodified. The list itself is unchanged (598 names).

## 1.0.1

- Changelog formatting fixes only; the library code is unchanged from 1.0.0.

## 1.0.0

- Add `slugify`, `namespacedKey` (naming the bad `NamespacedKeyField` on
  failure) and `fuzzyIncludes`.
- Add config merging and coercion: `JsonObject`, `deepClone`, `deepMerge`,
  `deepMergeAll`, `canonicalConfigKey`, `configKeysMatch`,
  `coerceEnvironmentScalar` and `environmentToNestedMap`. Keys match ignoring
  case and separators, the base spelling wins, `__` nests, digit segments build
  lists, blank values are unset, and JSON or comma text is never decoded.
- Add `isJsonObject`, `stableConfig` and `stableConfigObject`; a cycle is
  `record_unprojectable`.
- Add `WireDate`, `WireTime`, `IsoDuration`, `IanaTimezone`,
  `formatRfc3339Utc`, the strict `parseRfc3339Utc` (only `Z`),
  `normalizeRfc3339ToUtc` and `WireCodec`.
- Check timezone names against the bundled IANA release `2026b`.
- Export the shared temporal vectors as `c0TemporalContract` from
  `c0_temporal.dart`.
- Add `readVfsText`, `writeVfsText`, `readOptionalVfsText`, `ConfigLayer` and
  `loadConfigLayers` over the `Vfs` port from `diene_interfaces`.
- Add `sleep` and `mapWithConcurrency`.
- Report failures as `Result` values holding a `Problem` (`UtilName`,
  `UtilErrorCode`, `utilProblem`, `utilFailure`, `invalidUtilInput`,
  `invalidWireFormat`).
- Ship no `test_helper.dart`.
