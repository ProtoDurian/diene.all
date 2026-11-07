# diene_core_utils patterns

## Chain results instead of catching

```dart
final Result<String> cacheKey = namespacedKey(tenant, resource).andThen(
  (String key) => IanaTimezone.parse(zone).map((IanaTimezone z) => '$key@$z'),
);
final String shown = cacheKey.match(
  ok: (String key) => key,
  err: (Problem problem) => 'unusable: ${problem.detail}',
);
```

## Layer config, lowest precedence first

```dart
final JsonObject config = deepMergeAll(<JsonObject>[
  base,
  landscape,
  environmentToNestedMap(defines, prefix: 'ACME_').unwrap(),
]);
```

Keys match ignoring case, `-` and `_`, and the first layer's spelling stays:
`deepMerge({'display-name': 'a'}, {'DisplayName': 'b'})` is
`{display-name: b}`. `ACME_APP__TAGS__0=x` and `ACME_APP__TAGS__1=y` give
`{app: {tags: [x, y]}}`; `ACME_APP__TAGS=x,y` stays the string `x,y`.

## Load layers through a Vfs

```dart
final Result<JsonObject> config = await loadConfigLayers(vfs, <ConfigLayer>[
  ConfigLayer(path: 'config/base.yaml', parse: parseYaml),
  ConfigLayer(path: 'config/lapras.yaml', parse: parseYaml, optional: true),
]);
```

`parseYaml` is yours; this package has no parser. In tests pass an
`InMemoryVfs` from `package:diene_interfaces/test_helper.dart`.

## Instants

```dart
formatRfc3339Utc(DateTime.utc(2026, 7, 21, 1, 2, 3)); // Ok(2026-07-21T01:02:03.000Z)
parseRfc3339Utc('2026-07-21T01:02:03+00:00');          // Err: only Z is accepted
normalizeRfc3339ToUtc('2026-07-21T09:02:03+08:00');    // Ok(2026-07-21T01:02:03.000Z)
```

## Check your own temporal surface

```dart
import 'package:diene_core_utils/c0_temporal.dart';

for (final String date in c0TemporalContract.dates.valid) {
  // your parser must accept it
}
```

## Report your own failures

```dart
return invalidUtilInput<void>(
  util: UtilName.timing,
  operation: 'retry',
  field: 'attempts',
  message: 'attempts must be at least 1',
);
```
