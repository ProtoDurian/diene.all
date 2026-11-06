import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const POLICY = 'nix develop .#ci -c ./scripts/validate/release-policy.sh';
const CD = '.github/workflows/cd.yaml';
const TAG_PATTERN = "'v[0-9]+.[0-9]+.[0-9]+'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-tag-policy-green',
      description: 'release-policy validation accepts the v*.*.* CD tag trigger',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, POLICY, 'publish-tag-policy');
      },
    },
    {
      name: 'mutation-publish-tag-policy-caught',
      description: 'release-policy validation fails once CD triggers on a non-release tag pattern',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [CD], async () => {
          await repo.patch(CD, { find: TAG_PATTERN, replace: "'*'" });
          await expectRedBecause(repo, POLICY, 'publish-tag-policy', ['cd.yaml must trigger']);
        });
      },
    },
  ],
};
