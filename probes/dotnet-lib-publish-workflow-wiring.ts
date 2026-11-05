import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/dotnet.ts';

const WIRING = 'nix develop .#ci -c dlint ci-wiring';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-publish-workflow-wiring-green',
    description: 'The CD publish job resolves to its reusable workflow and entry script.',
    async run(repo: any) {
      await expectGreen(repo, WIRING, 'dotnet-lib-publish-workflow-wiring');
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-publish-workflow-wiring-caught',
    description: 'Pointing the publish job at a missing reusable workflow reddens ci-wiring.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('.github/workflows/cd.yaml', {
        find: 'uses: ./.github/workflows/⚡reusable-publish.yaml',
        replace: 'uses: ./.github/workflows/⚡missing-publish.yaml',
      });
      await expectRed(repo, WIRING, 'dotnet-lib-publish-workflow-wiring');
    },
  },
});
