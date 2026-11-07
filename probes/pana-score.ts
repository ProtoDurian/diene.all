import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const PANA =
  'nix develop .#ci -c bash -c \'export FLUTTER_ROOT=$(dirname "$(dirname "$(command -v flutter)")"); cd packages/diene_e2e && dart doc --dry-run && ../../scripts/validate/pana-score.sh\'';
const MEMBER_PUBSPEC = 'packages/diene_e2e/pubspec.yaml';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
  probes: [
    {
      name: 'baseline-pana-score-green',
      description: 'pana meets the documented score and warning policy',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, PANA, 'pana-score');
      },
    },
    {
      name: 'mutation-pana-score-caught',
      description: 'pana fails once the required package description is removed',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [MEMBER_PUBSPEC], async () => {
          const source = await repo.read(MEMBER_PUBSPEC);
          const stripped = source.replace(/^description:.*\n(?:[ \t]+.*\n)*/m, '');
          if (stripped === source) {
            throw new Error('pana-score: no description field to remove');
          }
          await repo.write(MEMBER_PUBSPEC, stripped);
          await expectRedBecause(repo, PANA, 'pana-score', ['pana lost']);
        });
      },
    },
  ],
};
