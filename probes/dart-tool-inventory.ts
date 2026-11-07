import { expectGreen } from './lib/helpers.ts';

const INVENTORY =
  "nix develop .#ci -c bash -c 'set -euo pipefail; dart --version; flutter --version; " +
  'export FLUTTER_ROOT=$(dirname "$(dirname "$(command -v flutter)")"); cd packages/diene_auth_engine; ' +
  '{ dart pub global run pana --help 2>&1 || true; } | grep -q -- --dartdoc-version; dart run coverage:format_coverage --help >/dev/null; ' +
  "dart run dart_code_linter:metrics --help >/dev/null; flutter test --help >/dev/null'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'nix develop .#ci -c flutter pub get --offline',
      'nix develop .#ci -c dart pub global activate pana 0.23.14',
      'rm -f .git/hooks/pre-commit .git/hooks/commit-msg',
    ],
  },
  probes: [
    {
      name: 'baseline-dart-tool-inventory-green',
      description: 'the ci shell exposes the pinned Dart SDK and each declared package tool runs',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, INVENTORY, 'dart-tool-inventory');
      },
    },
  ],
};
