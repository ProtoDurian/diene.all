import { expectGreen } from './lib/helpers.ts';

const DRY_RUN =
  "nix develop .#ci -c bash -c 'set -euo pipefail; cd packages/diene_api_engine; " +
  'out=$(dart pub publish --dry-run --skip-validation 2>&1); printf "%s\\n" "$out"; ' +
  'printf "%s\\n" "$out" | grep -Fx "Package has 0 warnings."\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-publish-dry-run-green',
      description: 'the publishable member builds its dry-run archive with zero warnings',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, DRY_RUN, 'publish-dry-run');
      },
    },
  ],
};
