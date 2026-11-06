import { expectGreen, expectRed } from './lib/helpers.ts';

const PANA =
  "nix develop .#ci --no-write-lock-file -c bash -lc 'cd packages/diene_dart_lib && dart doc --dry-run && ../../scripts/validate/pana-score.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci --no-write-lock-file -c dart pub get --offline'],
  },
  probes: [
    {
      name: 'baseline-pana-score-green',
      description: 'pana scores the pristine template perfectly (bar the unpublished mirror-main repository check)',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, PANA, 'pana-score');
      },
    },
    {
      name: 'mutation-pana-score-caught',
      description: 'pana fails once the package description is removed',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('packages/diene_dart_lib/pubspec.yaml', {
          find: 'description:',
          replace: '#description:',
        });
        await expectRed(repo, PANA, 'pana-score');
      },
    },
  ],
};
