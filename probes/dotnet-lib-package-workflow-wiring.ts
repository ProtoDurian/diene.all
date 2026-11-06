import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';
import { expectRedBecause } from './lib/dotnet-package.ts';

const WIRING = 'nix develop .#ci -c dlint ci-wiring';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-package-workflow-wiring-green',
    description: 'The CI package-validate job resolves to its reusable workflow and entry script.',
    async run(repo: any) {
      await expectGreen(repo, WIRING, 'dotnet-lib-package-workflow-wiring');
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-package-workflow-wiring-caught',
    description: 'Pointing the package-validate job at a missing reusable workflow reddens ci-wiring.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('.github/workflows/ci.yaml', {
        find: 'uses: ./.github/workflows/⚡reusable-package-validate.yaml',
        replace: 'uses: ./.github/workflows/⚡missing-package-validate.yaml',
      });
      await expectRedBecause(repo, WIRING, 'dotnet-lib-package-workflow-wiring', [
        'references missing reusable workflow',
      ]);
    },
  },
});
