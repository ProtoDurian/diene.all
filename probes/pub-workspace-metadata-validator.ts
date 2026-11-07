import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const VALIDATOR = 'nix develop .#ci -c ./scripts/validate/dart-package.sh';
const MEMBER_PUBSPEC = 'packages/diene_e2e/pubspec.yaml';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-pub-workspace-metadata-validator-green',
      description: 'the package validator accepts the workspace wiring, identity and required artifacts',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, VALIDATOR, 'pub-workspace-metadata-validator');
      },
    },
    {
      name: 'mutation-pub-workspace-metadata-validator-caught',
      description: 'the validator rejects the publishable member once it is disconnected from the workspace',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [MEMBER_PUBSPEC], async () => {
          await repo.patch(MEMBER_PUBSPEC, { find: 'resolution: workspace\n', replace: '' });
          await expectRedBecause(repo, VALIDATOR, 'pub-workspace-metadata-validator', ['resolution: workspace']);
        });
      },
    },
  ],
};
