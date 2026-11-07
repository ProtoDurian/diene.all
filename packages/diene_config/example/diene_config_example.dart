import 'package:diene_config/diene_config.dart';
import 'package:diene_result/diene_result.dart';

final ConfigBlock<List<Object?>> apiBlock = ConfigBlock<List<Object?>>(
  key: 'api',
  decode: (Map<String, Object?> values) => values['scopes']! as List<Object?>,
);

Future<void> main() async {
  final Result<DieneConfig> loaded = await ConfigLoader(
    base: YamlConfigSource.string(
      'api:\n  baseUrl: https://api.local.test\n  scopes: [openid]\n',
      name: 'base.yaml',
    ),
    overlay: YamlConfigSource.string(
      'api:\n  baseUrl: https://api.lapras.test\n',
      name: 'lapras.yaml',
    ),
    dartDefines: const DartDefineOverrides(
      prefix: 'ACME_',
      values: <String, String>{
        'ACME_API__SCOPES__0': 'openid',
        'ACME_API__SCOPES__1': 'profile',
      },
    ),
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock]),
  ).load();

  final DieneConfig config = loaded.unwrap();
  assert(
    config.slice(apiBlock).join(',') == 'openid,profile',
    'indexed defines replace the YAML list',
  );
  assert(
    config.rawSlice('api').unwrap()['baseUrl'] == 'https://api.lapras.test',
    'the overlay wins over the base',
  );

  final Result<String> track = landscape(
    source: const DartDefineLandscapeSource(value: 'lapras'),
  );
  assert(track.unwrap() == 'lapras', 'the landscape is injected');
}
