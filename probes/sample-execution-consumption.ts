import { expectGreen, withCleanProbeState } from './lib/helpers.ts';

const CONSUMER = '.probe-consumer';
const CONSUMER_PUBSPEC =
  'name: probe_consumer\npublish_to: none\nenvironment:\n  sdk: ">=3.12.0 <4.0.0"\n' +
  'dependencies:\n  diene_core_utils:\n    path: @ROOT@/packages/diene_core_utils\n';
const CONSUMER_MAIN =
  "import 'package:diene_core_utils/c0_temporal.dart' as c0;\n" +
  "import 'package:diene_core_utils/diene_core_utils.dart';\n\n" +
  'Future<void> main() async {\n' +
  "  final String key = namespacedKey('Diene', 'Crème Brûlée').unwrap();\n" +
  "  final String date = const WireCodec().decodeDate('2026-11-07').unwrap().toString();\n" +
  '  final bool zones = c0.c0TemporalContract.timezones.valid.every(isIanaTimeZone);\n' +
  "  final int merged = deepMerge(<String, Object?>{'a': 1}, <String, Object?>{'b': 2}).length;\n" +
  "  print('$key $date $zones $merged ${(await sleep(Duration.zero)).isOk}');\n" +
  '}\n';

// The consumer is copied outside the workspace so pub resolves it as a stranger would.
const RUN =
  "nix develop .#ci -c bash -c 'set -euo pipefail; root=$(pwd -P); " +
  '(cd packages/diene_core_utils && for example in example/*.dart; do dart run "$example"; done); ' +
  `consumer=$(mktemp -d); cp -R ${CONSUMER}/. "$consumer"/; sed -i "s|@ROOT@|$root|" "$consumer/pubspec.yaml"; ` +
  'cd "$consumer"; dart pub get --offline; dart run bin/main.dart | grep -Fx "diene:creme-brulee 2026-11-07 true 2 true"\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-sample-execution-consumption-green',
      description: 'the example runs and a clean local consumer calls the barrel and the c0_temporal sub-library',
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
