# diene_config

[![pub package](https://img.shields.io/pub/v/diene_config.svg)](https://pub.dev/packages/diene_config)
[![CI](https://github.com/ProtoDurian/diene.dart_config/actions/workflows/ci.yaml/badge.svg)](https://github.com/ProtoDurian/diene.dart_config/actions/workflows/ci.yaml)

Layered configuration for Dart and Flutter apps. A full base YAML, a sparse
flavor or landscape YAML, an optional development override and then
`--dart-define` values are merged in that order, and the final tree is
validated once against a root schema the service composes from engine-owned
blocks.

```dart
import 'package:diene_config/diene_config.dart';
import 'package:diene_result/diene_result.dart';

final ConfigBlock<Uri> apiBlock = ConfigBlock<Uri>(
  key: 'api',
  decode: (Map<String, Object?> values) =>
      Uri.parse(values['baseUrl']! as String),
);

Future<void> main() async {
  final Result<DieneConfig> loaded = await ConfigLoader(
    base: YamlConfigSource.string('api:\n  baseUrl: https://api.example.test'),
    dartDefines: const DartDefineOverrides(
      prefix: 'MY_APP_',
      values: <String, String>{
        'MY_APP_API__BASE_URL': String.fromEnvironment('MY_APP_API__BASE_URL'),
      },
    ),
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock]),
  ).load();
  final Uri baseUrl = loaded.unwrap().slice(apiBlock);
}
```

## Public surface

- `ConfigLoader`, `YamlConfigSource`, `ConfigSource`, `DartDefineOverrides`:
  the layers and their fixed order.
- `ConfigSchema`, `ConfigBlock<T>`, `ConfigBlockSchema`, `DieneConfig`: the
  composed root schema, final validation and typed slices.
- `landscape()`, `LandscapeSource`, `DartDefineLandscapeSource`: the landscape
  passed in with `--dart-define=DIENE_LANDSCAPE=<track>`, never detected.
- `ConfigProblemCode`, `configProblem`, `configFailure`, `configProblemCode`:
  failures as RFC 9457 `Problem` values.
- `package:diene_config/c0_config.dart`: `c0ConfigContract`, the shared
  contract release this package is checked against.
- `package:diene_config/config/app_config.dart`: `AppConfig`, a migration aid.

## TestHelper

`package:diene_config/test_helper.dart` has fake layers, a stub builder, a fake
harness over the real loader, and assertions. It imports no test framework.

Read the [package doc](doc/diene_config.md) for layer order, schemas, indexed
lists, failures and the TestHelper.

## Development

- `task setup` resolves the workspace dependencies.
- `task test` runs the unit, conformance and TestHelper meta suites.
- `task test:coverage` checks the separate unit and meta coverage.
- `task deadcode` runs both dead-code passes.
- `task package:validate` runs the release guard, publish dry-run and pana.
