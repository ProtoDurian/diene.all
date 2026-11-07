# diene_config

`diene_config` loads layered YAML configuration, merges it, validates the final
tree once, and hands out typed slices. It owns the loading, the merge order and
the final validation. It owns no engine's schema and no merge code of its own:
`deepMergeAll`, `canonicalConfigKey`, `environmentToNestedMap` and
`stableConfig` come from the published `diene_core_utils`.

## Layer order

`ConfigLoader.load()` reads the layers in this fixed order. A later layer wins
on a shared key; a key no later layer sets keeps its earlier value.

1. `base`: a full YAML document with every key and its default.
2. `overlay`: one sparse flavor or landscape YAML.
3. `developmentOverride`: an optional local hook (see below).
4. `dartDefines`: enumerated `--dart-define` values, always last.

Then the composed schema validates the merged tree, once. Maps merge key by
key; a list or a scalar replaces the earlier value whole. Keys match ignoring
case, `-` and `_`, and the base layer's spelling is kept.

Configuration is immutable after loading. There is no watch or reload API.

## Three-layer injection in Dart

Dart has three ways to get values in: YAML text, a flavor or landscape YAML,
and `--dart-define` values fixed at compile time. The package reads none of
them by itself:

- YAML comes through `YamlConfigSource(name:, read:)`, where `read` returns the
  text. Flutter passes `rootBundle.loadString`, a command-line app passes
  `File(path).readAsString`, and a test passes a string. The package imports
  neither Flutter nor `dart:io`.
- Defines are enumerated by the app. `String.fromEnvironment` only works with a
  literal key, so the app lists the keys it accepts:

```dart
dartDefines: const DartDefineOverrides(
  prefix: 'ACME_',
  values: <String, String>{
    'ACME_API__BASE_URL': String.fromEnvironment('ACME_API__BASE_URL'),
  },
),
```

## The development override hook

`developmentOverride` is any `ConfigSource`. It applies after the overlay and
before the defines, so a local file can change a landscape value while a define
still wins. Pass `null` (the default) in a release build and the layer is
skipped.

## Engine-owned schemas

Each engine (auth, API, ...) exports its own `ConfigBlock<T>` next to the code
that reads it. The service composes those blocks with its own into one
`ConfigSchema`:

```dart
final ConfigSchema schema = ConfigSchema(
  blocks: <ConfigBlockSchema>[authBlock, apiBlock, appBlock],
);
```

A block's `decode` gets the final merged map for its key and returns the typed
value or throws. This package never defines another package's block. A
duplicate, empty or `$schema` block key throws `ArgumentError` when the schema
is built, because the block list is code, not input.

## Final-only validation

Only the final merged tree is validated. A base that is incomplete or invalid
on its own is fine when a later layer fixes it, and no intermediate tree is
ever exposed. A failed validation returns one `schema_invalid` problem whose
`data.errors` lists every error found: a missing required block, a block that
is not a map, a decoder that threw, two root keys that collide, and (with
`rejectUnknownBlocks`, the default) a root key with no block.

## Defines and indexed lists

The prefix is chosen by the app and matched ignoring case, `-` and `_`, like the
rest of the key. `__` separates path parts. A list is written with indexed keys
that replace the YAML list whole:

```text
ACME_AUTH__SCOPES__0=openid
ACME_AUTH__SCOPES__1=offline_access
```

A JSON value (`["openid","profile"]`) or a comma value (`openid,profile`) is
never decoded: it stays a string, and a block that expects a list rejects it. A
blank value is unset and cannot erase a base value. `true`/`false`, safe
integers and decimals are converted; anything else stays a string. A bad key
(an empty part, a gap in an index, a scalar used as a parent) returns the
`diene_core_utils` problem unchanged.

## Landscape

`landscape()` returns the landscape the build was given with
`--dart-define=DIENE_LANDSCAPE=<track>`. On mobile, the store track is the
landscape. It reads that value and nothing else: no host name, environment or
network check. A missing or blank value is `landscape_missing`. Tests pass
`landscape(source: const DartDefineLandscapeSource(value: 'lapras'))` or the
TestHelper's `FakeLandscapeSource`.

## Typed slices

`DieneConfig` gives:

- `slice(block)`: the value from that block's decoder;
- `hasSlice(block)` / `optionalSlice(block)`: for a `required: false` block;
- `rawSlice(key)`: an untyped block, matched like any other key;
- `raw`: the whole merged tree, unmodifiable at every depth;
- `stableProjection()`: the tree with sorted keys, for hashing or diffs.

Keep the `ConfigBlock` instances you composed and pass the same objects to
`slice`. A new block with the same key was not composed: `hasSlice` is `false`
and `slice` throws `StateError`.

## Failures

Every expected failure is an `Err` holding an RFC 9457 `Problem` from
`diene_problems`; `load()` does not throw for bad configuration.

| Code                | Status | Cause                                             |
| ------------------- | ------ | ------------------------------------------------- |
| `source_unreadable` | 422    | a layer's `read` threw, or its YAML did not parse |
| `source_not_a_map`  | 422    | a layer parsed but its root is not a map          |
| `schema_invalid`    | 422    | the final merged tree failed validation           |
| `landscape_missing` | 400    | no `DIENE_LANDSCAPE` value was given              |

`configProblemCode(problem)` returns the code for a problem this package made
and `None` for any other, such as a `diene_core_utils` define problem. The
`data` keys `code` and `x-diene-config-provenance` are reserved.

## TestHelper

`package:diene_config/test_helper.dart` ships in the package and imports no test
framework. A failed assertion throws `ConfigAssertionFailure` (a `StateError`),
so any test runner reports it.

- `FakeConfigSource`, `FailingConfigSource`: in-memory layers, one that always
  fails; `FakeConfigSource.loadCount` counts reads.
- `FakeLandscapeSource`: a fixed landscape.
- `ConfigStubBuilder`: builds a `DieneConfig` through the real
  `ConfigSchema.validate`, so a stub cannot be something the loader rejects.
- `FakeConfigHarness`: the real `ConfigLoader` over in-memory layers.
- `expectOkConfig`, `expectErrConfig`, `assertConfigProblem`,
  `assertConfigSlice`: assertions over the result.

The package's meta tests run the same cases through the real loader with real
YAML and through these fakes, and check both give the same result.

## Migrating from an in-app `config/app_config.dart`

`package:diene_config/config/app_config.dart` re-exports the package and adds
`AppConfig`, a process-wide holder (`install`, `instance`, `maybeInstance`,
`loadAndInstall`, `reset`). Reading `instance` before `install` throws, and a
second `install` needs `force: true`. It is a migration aid; new code passes
`DieneConfig` explicitly.

## Shared contract checks

`package:diene_config/c0_config.dart` exports `c0ConfigContract`, the identity
of the shared config contract release (`c0-fixtures-r2`) this package is
checked against. The package tests keep pinned copies of that release's config
cases (layer order with indexed lists, blank is unset, key matching, no JSON or
comma lists, final-only validation) and run each one through the real loader.

## Parity with the other languages

The same in every language: full base, sparse overlay, development hook,
injected values last; one validation of the final tree; engine-owned schema
blocks; indexed lists; no JSON or comma lists; blank is unset.

Different in Dart:

- Defines are enumerated by the app, because Dart cannot list compile-time
  values at run time.
- There is no standard-config package for Dart, and this package does not stand
  in for one: it owns merge and validation only.
- There is no OpenTelemetry config block: the Dart family runs in the frontend.
- Schemas are typed decoder callbacks, so an engine needs no extra dependency
  to describe its settings.
- The landscape accessor lives here.
