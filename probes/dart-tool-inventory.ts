import { expectGreen } from './lib/helpers.ts';

const INVENTORY =
  "nix develop .#ci -c bash -c 'set -euo pipefail; dart --version; cd packages/diene_auth_engine; " +
  '{ dart run pana --help 2>&1 || true; } | grep -q -- --dartdoc-version; dart run coverage:format_coverage --help >/dev/null; ' +
  "dart run dart_code_linter:metrics --help >/dev/null; dart test --help >/dev/null'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
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
