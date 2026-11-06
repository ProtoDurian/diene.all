import { expectGreen, withCleanProbeState } from './lib/helpers.ts';

const CONSUMER = '.probe-consumer';
const CONSUMER_PUBSPEC =
  'name: probe_consumer\npublish_to: none\nenvironment:\n  sdk: ">=3.12.0 <4.0.0"\n' +
  'dependencies:\n  diene_dart_lib:\n    path: @ROOT@/packages/diene_dart_lib\n';
const CONSUMER_MAIN =
  "import 'package:diene_dart_lib/diene_dart_lib.dart';\n\n" +
  "void main() {\n  print(summarizeNote(const Note(title: 'Probe', body: 'consumer')));\n}\n";

// The consumer is copied outside the workspace so pub resolves it as a stranger would.
const RUN =
  "nix develop .#ci -c bash -c 'set -euo pipefail; root=$(pwd -P); " +
  '(cd packages/diene_dart_lib && for example in example/*.dart; do dart run "$example"; done); ' +
  `consumer=$(mktemp -d); cp -R ${CONSUMER}/. "$consumer"/; sed -i "s|@ROOT@|$root|" "$consumer/pubspec.yaml"; ` +
  'cd "$consumer"; dart pub get --offline; dart run bin/main.dart | grep -F "Probe"\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline'] },
  probes: [
    {
      name: 'baseline-sample-execution-consumption-green',
      description: 'the example runs and a clean local consumer imports the public barrel',
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
