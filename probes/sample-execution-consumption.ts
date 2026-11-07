import { expectGreen, withCleanProbeState } from './lib/helpers.ts';

const CONSUMER = '.probe-consumer';
const CONSUMER_PUBSPEC =
  'name: probe_consumer\npublish_to: none\nenvironment:\n  sdk: ">=3.12.0 <4.0.0"\n' +
  'dependencies:\n  diene_api_engine:\n    path: @ROOT@/packages/diene_api_engine\n  diene_result: ^1.0.0\n' +
  'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n';
const CONSUMER_TEST =
  "import 'package:diene_api_engine/diene_api_engine.dart';\n" +
  "import 'package:flutter_test/flutter_test.dart';\n\n" +
  "void main() {\n  test('consumer', () {\n" +
  "    print(const LpsmCoordinate(landscape: 'lapras', platform: 'probe', service: 'api', module: 'root').key);\n" +
  '  });\n}\n';

// The barrel needs dart:ui, so the examples and the consumer run under flutter test, not dart run.
// The consumer is copied outside the workspace so pub resolves it as a stranger would.
const RUN =
  "nix develop .#ci -c bash -c 'set -euo pipefail; root=$(pwd -P); " +
  `consumer=$(mktemp -d); cp -R ${CONSUMER}/. "$consumer"/; sed -i "s|@ROOT@|$root|" "$consumer/pubspec.yaml"; ` +
  'mkdir -p "$consumer/test/examples"; runner="$consumer/test/examples_test.dart"; n=0; ' +
  'for example in packages/diene_api_engine/example/*.dart; do cp "$example" "$consumer/test/examples/e$n.dart"; ' +
  'printf "import \\x27examples/e%s.dart\\x27 as e%s;\\n" "$n" "$n" >>"$runner"; n=$((n + 1)); done; ' +
  '[ "$n" -gt 0 ] || { echo "no example to run" >&2; exit 1; }; ' +
  'printf "import \\x27package:flutter_test/flutter_test.dart\\x27;\\n\\nvoid main() {\\n" >>"$runner"; ' +
  'for i in $(seq 0 $((n - 1))); do printf "  test(\\x27example %s\\x27, () async => await e%s.main());\\n" "$i" "$i" >>"$runner"; done; ' +
  'printf "}\\n" >>"$runner"; ' +
  'cd "$consumer"; flutter pub get --offline; out=$(flutter test --reporter=expanded); printf "%s\\n" "$out"; grep -F "lapras.probe.api.root" <<<"$out"\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
  probes: [
    {
      name: 'baseline-sample-execution-consumption-green',
      description: 'the examples run and a clean local consumer imports the public barrel',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, [CONSUMER], async () => {
          await repo.write(`${CONSUMER}/pubspec.yaml`, CONSUMER_PUBSPEC);
          await repo.write(`${CONSUMER}/test/consumer_test.dart`, CONSUMER_TEST);
          await expectGreen(repo, RUN, 'sample-execution-consumption');
        });
      },
    },
  ],
};
