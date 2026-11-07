# diene_config patterns

## Compose a root schema from engine blocks

```dart
final ConfigSchema schema = ConfigSchema(
  blocks: <ConfigBlockSchema>[authBlock, apiBlock, appBlock],
);
final Result<DieneConfig> loaded = await ConfigLoader(
  base: YamlConfigSource(name: 'base.yaml', read: readBase),
  overlay: YamlConfigSource(name: 'lapras.yaml', read: readLandscape),
  dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
  schema: schema,
).load();
```

## Reject input from a decoder

```dart
final ConfigBlock<AppSettings> appBlock = ConfigBlock<AppSettings>(
  key: 'app',
  decode: (Map<String, Object?> values) {
    final Object? retries = values['retries'];
    if (retries is! int || retries < 0) {
      throw FormatException('retries must be a non-negative int');
    }
    return AppSettings(retries: retries);
  },
);
```

The throw becomes one line of the `schema_invalid` problem's `data.errors`.

## Test with fakes

```dart
final DieneConfig config = expectOkConfig(
  await FakeConfigHarness(
    base: <String, Object?>{'app': <String, Object?>{'retries': 1}},
    defines: <String, String>{'TEST_APP__RETRIES': '3'},
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[appBlock]),
  ).load(),
);
```
