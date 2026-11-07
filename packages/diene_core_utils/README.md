# diene_core_utils

[![pub package](https://img.shields.io/pub/v/diene_core_utils.svg)](https://pub.dev/packages/diene_core_utils)
[![CI](https://github.com/ProtoDurian/diene.dart_core_utils/actions/workflows/ci.yaml/badge.svg)](https://github.com/ProtoDurian/diene.dart_core_utils/actions/workflows/ci.yaml)

Pure Dart utilities: slugs and namespaced keys, layered configuration merges,
environment coercion, bounded concurrency, and the canonical date, time,
instant, duration and IANA timezone wire forms. Every fallible member returns a
[`diene_result`](https://pub.dev/packages/diene_result) `Result` whose error is
a [`diene_problems`](https://pub.dev/packages/diene_problems) `Problem`;
nothing throws for an expected failure.

The package imports no `dart:io`, so it runs on the VM, the web and Flutter. Its
only outside-world access is the injected `Vfs` port from
[`diene_interfaces`](https://pub.dev/packages/diene_interfaces).

```sh
dart pub add diene_core_utils
```

```dart
import 'package:diene_core_utils/diene_core_utils.dart';

final String slug = slugify('Crème Brûlée'); // creme-brulee
final String key = namespacedKey('Billing', 'Invoice Total').unwrap();
final JsonObject config = deepMergeAll(<JsonObject>[
  <String, Object?>{'app': <String, Object?>{'displayName': 'base'}},
  environmentToNestedMap(
    <String, String>{'ACME_APP__DISPLAY_NAME': 'prod'},
    prefix: 'ACME_',
  ).unwrap(),
]); // {app: {displayName: prod}}
final String at = formatRfc3339Utc(DateTime.utc(2026, 7, 21)).unwrap();
```

## Public surface

- Identity: `slugify`, `namespacedKey`, `NamespacedKeyField`, `fuzzyIncludes`.
- Configuration: `JsonObject`, `deepClone`, `deepMerge`, `deepMergeAll`,
  `canonicalConfigKey`, `configKeysMatch`, `coerceEnvironmentScalar`,
  `environmentPathSeparator`, `environmentToNestedMap`, `isJsonObject`,
  `stableConfig`, `stableConfigObject`.
- Config over a `Vfs`: `readVfsText`, `writeVfsText`, `readOptionalVfsText`,
  `ConfigLayer`, `loadConfigLayers`.
- Wire forms: `WireDate`, `WireTime`, `IsoDuration`, `IanaTimezone`,
  `isIanaTimeZone`, `ianaTimeZoneRelease`, `formatRfc3339Utc`,
  `parseRfc3339Utc`, `normalizeRfc3339ToUtc`, `WireCodec`, the `wire*Grammar`
  constants.
- Timing: `sleep`, `mapWithConcurrency`.
- Failures: `UtilName`, `UtilErrorCode`, `coreUtilsProblemVersion`,
  `utilProblem`, `utilFailure`, `invalidUtilInput`, `invalidWireFormat`.
- `package:diene_core_utils/c0_temporal.dart`: `c0TemporalContract`, the shared
  temporal test vectors other Diene Dart packages check themselves with.

## TestHelper

None. Every member is a pure function or a pass-through over the injected
`Vfs`, and `diene_interfaces` already ships `InMemoryVfs`, so there is nothing
to fake. The [usage skill](skills/diene-core-utils-usage/SKILL.md) says how to
add one if that changes.

Read the [package doc](doc/diene_core_utils.md) for the full contract.

## Development

- `task setup` resolves the workspace dependencies.
- `task test` runs the unit and conformance suites; the meta tier has nothing
  to run.
- `task test:coverage` enforces the 100% unit coverage ledger.
- `task deadcode` runs the repository and production-only dead-code passes.
- `task package:validate` runs the release guard, publish dry-run and pana.
