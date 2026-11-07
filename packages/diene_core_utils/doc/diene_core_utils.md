# diene_core_utils

`diene_core_utils` is the Dart family's small, deterministic utility layer. It
owns slugs, config merging and coercion, and the canonical temporal wire forms.
It owns no port and no adapter: those live in `diene_interfaces`.

## Failures are `Result` values

Every fallible member returns `Result<T>` (or `Future<Result<T>>`) from
`diene_result` and never throws for an expected failure. The error is a
`Problem` from `diene_problems`.

- `utilProblem` is the one place a failure becomes a `Problem`. Its `type`
  comes from `problemTypeUri`, version `v1`, id `<util>_<code>` (for example
  `wire_invalid_format`), on `ErrorPortal.localError` unless you pass a portal.
- `UtilName`: `slug`, `coercion`, `record`, `wire`, `concurrency`, `timing`,
  `vfs`. `UtilErrorCode`: `invalid_input` (400), `invalid_format` (400),
  `conflict` (409), `unprojectable` (422), `delegated` (500).
- `recoverable` is always `false`: each failure depends only on the input.
- `data` always holds `util`, `code` and `operation`, plus details such as
  `field`, `expected` or `value`. `instance` is never set.

## Identity

| Member          | Behaviour                                                                                                                                      |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `slugify`       | NFKD, drop combining marks, lowercase, trim, join every run of non `a-z0-9` characters with one `-`, strip edge `-`. Never fails; may be `''`. |
| `namespacedKey` | Slugifies both parts and joins them as `namespace:key`. A part that slugifies to `''` is `slug_invalid_input` with `field` = the part's name.  |
| `fuzzyIncludes` | Case-insensitive substring test; an empty needle always matches.                                                                               |

## Configuration

| Member                    | Behaviour                                                                                                                                       |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `deepMerge`               | Maps merge recursively; lists and scalars replace. Keys match ignoring case, `-` and `_`; the base layer's spelling stays the output key.       |
| `deepMergeAll`            | Merges layers lowest precedence first: base, then overlays, then defines.                                                                       |
| `canonicalConfigKey`      | Drops `-` and `_` and lowercases: `display-name`, `display_name` and `DisplayName` all match.                                                   |
| `coerceEnvironmentScalar` | Blank is `null` (unset); `true`/`false` in any case are booleans; safe integers are `int`; decimals are `double`; anything else stays a string. |
| `environmentToNestedMap`  | Picks keys by prefix (any case). `__` nests, all-digit segments build lists, blank values are left out. JSON or comma text is never decoded.    |
| `stableConfig`            | Clones with keys sorted at every depth and list order kept, so equal configs give equal JSON. A cycle is `record_unprojectable`.                |

Money and exact decimals never go through `coerceEnvironmentScalar`: they stay
decimal strings. Integers beyond 2^53 stay strings too.

`environmentToNestedMap` reports a bad key as `coercion_invalid_input` (empty
path segment, sparse or mixed list indexes) or `coercion_conflict` (two keys on
one path, or a scalar used as a parent).

## The `Vfs` boundary

`readVfsText`, `writeVfsText` (creates parent directories),
`readOptionalVfsText` (a missing path is `Ok(null)`), `ConfigLayer` and
`loadConfigLayers` are the only members that touch the outside world, and only
through a `Vfs` you pass in. The package imports no `dart:io`, `dart:isolate`
or `dart:ffi`.

- A `Vfs` failure comes back unchanged, with its own status and `recoverable`.
- `ConfigLayer.parse` turns text into a `JsonObject`; the package has no YAML
  or JSON parser of its own.
- `loadConfigLayers` stops at the first failure. An optional layer that is
  missing adds nothing; when no layer exists at all it is `vfs_invalid_input`.
- Test it with `InMemoryVfs` from `package:diene_interfaces/test_helper.dart`.

## Wire forms

| Value    | Member                                 | Wire form                                                         |
| -------- | -------------------------------------- | ----------------------------------------------------------------- |
| Date     | `WireDate.parse` / `WireDate.of`       | `YYYY-MM-DD`, a real calendar date, year 1 to 9999                |
| Time     | `WireTime.parse` / `WireTime.of`       | `HH:MM:SS`, no leap second                                        |
| Instant  | `formatRfc3339Utc`, `parseRfc3339Utc`  | UTC ending in `Z`; the parser rejects every offset, even `+00:00` |
| Instant  | `normalizeRfc3339ToUtc`                | takes `Z` or an offset once, at the boundary, and returns UTC     |
| Duration | `IsoDuration.parse`                    | ISO 8601, kept as written (a decimal comma becomes a point)       |
| Timezone | `IanaTimezone.parse`, `isIanaTimeZone` | exact name from the bundled IANA release `2026b` (598 names)      |
| All      | `const WireCodec()`                    | one object with every encode and decode                           |

A zoned value is two fields, the instant and the timezone name; there is no
combined type. Timezone names come from the official IANA archive, never from
the host's zone files: `EST`, `GMT` and `US/Eastern` are valid, `PST` and
`+08:00` are not.

Differences from the repository wire-format standard (kept for compatibility
with 1.0.x; candidates for 2.0):

- `formatRfc3339Utc` writes 6 fractional digits when the `DateTime` has
  microseconds; the standard says exactly 3.
- `parseRfc3339Utc` accepts any number of fractional digits, including none;
  the standard writes exactly 3.
- `IsoDuration` keeps the designation as written (`PT90M`, `P1W`) instead of
  the normal form.

## Shared temporal vectors

`package:diene_core_utils/c0_temporal.dart` exports `c0TemporalContract`: valid
and invalid dates, times, durations, timezones and instants. Other Diene Dart
packages check their own surface against it instead of copying cases. Its
`contentSha256` is the digest of `digestPayload()`, so a changed vector needs a
deliberate digest update.

## TestHelper: none

There is no `lib/test_helper.dart` and no helper package. Every member is a
pure function or a pass-through over a `Vfs` you inject, and `diene_interfaces`
already ships `InMemoryVfs`, so there is nothing to fake and no assertion worth
sharing. The meta test tier finds no TestHelper and passes without running or
writing coverage.

## Parity with the Bun core-utils

| Bun                                        | Dart                                                               | Why                                                                                                                           |
| ------------------------------------------ | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `Slugger.slugify`, `Slugger.namespacedKey` | `slugify`, `namespacedKey`                                         | Same transform. Dart uses free functions and `unorm_dart` for NFKD; the failure is a `Problem` naming a `NamespacedKeyField`. |
| `NamespacedKeyValidationError`             | none                                                               | The family's one error type is `Problem`.                                                                                     |
| `Timing.sleep(seconds)`, `Timing.noop`     | `sleep(Duration)`                                                  | Dart has `Duration`; a negative one is an `Err`, not a throw. `() {}` is Dart's no-op.                                        |
| `RecordTools.isRecord`, `stableConfig`     | `isJsonObject`, `stableConfig`, `stableConfigObject`               | "record" is a Dart language feature. A cycle is an `Err`, not a `TypeError`.                                                  |
| `FuzzyMatcher.fuzzyIncludes`               | `fuzzyIncludes`                                                    | Same.                                                                                                                         |
| `ConcurrencyMapper.mapWithConcurrency`     | `mapWithConcurrency`                                               | The mapper returns a `Result`; the lowest failing index wins. A bound below 1 is an `Err`.                                    |
| `Hasher`, `Deduper`                        | none                                                               | Use `package:crypto` and `toSet().toList()` directly.                                                                         |
| `SafePath.safeJoin`                        | none                                                               | Path rules belong to a `Vfs` implementation (`diene_interfaces` has `checkVfsPath`).                                          |
| `WireDateCodec` over `Temporal`            | `WireDate`, `WireTime`, `IsoDuration`, `IanaTimezone`, `WireCodec` | Dart has no `Temporal`, so validated value types hold the rules. Dart adds `normalizeRfc3339ToUtc` for offset input.          |
| none                                       | config merging, env coercion, `Vfs` config loading                 | Dart additions for the Dart config package and Flutter; Bun core-utils has no counterpart.                                    |
| none                                       | `c0TemporalContract`                                               | Shared temporal vectors for the Dart family.                                                                                  |

## Conformance

- `test/fixtures/c0/upstream/` holds four config cases copied unchanged from
  the shared C0 release `contracts/c0/cases/config.json`: blank is unset,
  case-insensitive keys, layering with indexed lists, and no JSON or comma
  lists. `manifest.json` pins the commit, the file digest, each case's pointer
  and digest, the stored file bytes and a `reproduce` command.
- `test/fixtures/c0/` holds local fixtures (`local-regression-only`): the
  temporal vectors, one value of each wire form, and one wire-form `Problem`.
- The IANA archive `third_party/iana-tzdata-2026b/tzdata2026b.tar.gz` sits at
  the repository root, outside the package. A test checks its digest against
  `c0TemporalContract` and that `lib/src/iana_zones.dart` is exactly what
  `tool/gen_iana_zones.dart` generates from it.
