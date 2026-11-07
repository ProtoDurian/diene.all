import { expectGreen, withCleanProbeState } from './lib/helpers.ts';

const CONSUMER = '.probe-consumer';
const CONSUMER_PUBSPEC =
  'name: probe_consumer\npublish_to: none\nenvironment:\n  sdk: ">=3.12.0 <4.0.0"\n' +
  'dependencies:\n  diene_config:\n    path: @ROOT@/packages/diene_config\n';
const CONSUMER_MAIN = [
  "import 'package:diene_config/c0_config.dart' as c0;",
  "import 'package:diene_config/config/app_config.dart' show AppConfig;",
  "import 'package:diene_config/diene_config.dart';",
  "import 'package:diene_config/test_helper.dart';",
  '',
  'final ConfigBlock<String> probeBlock = ConfigBlock<String>(',
  "  key: 'probe',",
  "  decode: (Map<String, Object?> v) => '${v['name']} ${(v['tags']! as List<Object?>).join('+')}',",
  ');',
  '',
  'Future<void> main() async {',
  '  final ConfigLoader loader = ConfigLoader(',
  "    base: YamlConfigSource.string('probe:\\n  name: base\\n  tags: [a]\\n'),",
  "    overlay: YamlConfigSource.string('probe:\\n  name: overlay\\n'),",
  "    dartDefines: const DartDefineOverrides(prefix: 'PROBE_', values: <String, String>{",
  "      'PROBE_PROBE__NAME': 'define', 'PROBE_PROBE__TAGS__0': 'x', 'PROBE_PROBE__TAGS__1': 'y',",
  '    }),',
  '    schema: ConfigSchema(blocks: <ConfigBlockSchema>[probeBlock]),',
  '  );',
  '  AppConfig.install(expectOkConfig(await loader.load()));',
  "  final String track = landscape(source: const FakeLandscapeSource('beta')).unwrap();",
  "  print('${AppConfig.instance.slice(probeBlock)} $track ${c0.c0ConfigContract.projectedCases.isNotEmpty}');",
  '}',
  '',
].join('\n');

// The consumer is copied outside the workspace so pub resolves it as a stranger would.
const RUN =
  "nix develop .#ci -c bash -c 'set -euo pipefail; root=$(pwd -P); " +
  '(cd packages/diene_config && for example in example/*.dart; do dart run "$example"; done); ' +
  `consumer=$(mktemp -d); cp -R ${CONSUMER}/. "$consumer"/; sed -i "s|@ROOT@|$root|" "$consumer/pubspec.yaml"; ` +
  'cd "$consumer"; dart pub get --offline; dart run bin/main.dart | grep -Fx "define x+y beta true"\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-sample-execution-consumption-green',
      description:
        'the example runs and a clean local consumer loads layers through the barrel, helper, app_config and c0_config',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, [CONSUMER], async () => {
          await repo.write(`${CONSUMER}/pubspec.yaml`, CONSUMER_PUBSPEC);
          await repo.write(`${CONSUMER}/bin/main.dart`, CONSUMER_MAIN);
          await expectGreen(repo, RUN, 'sample-execution-consumption');
        });
      },
    },
  ],
};
