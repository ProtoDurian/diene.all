import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const command = 'nix develop .#ci -c ./scripts/validate/release-lint.sh vocabulary';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-release-vocabulary-green',
    description: 'release.yaml declares the dep type and not the retired upstream type.',
    async run(repo: any) {
      await expectGreen(repo, command, 'wrapper-release-vocabulary');
    },
  },
  mutation: {
    name: 'mutation-wrapper-release-vocabulary-caught',
    description: 'Removing the dep type is rejected.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'release.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, { find: '  - type: dep\n', replace: '  - type: dependency\n' });
        await expectRed(repo, command, 'wrapper-release-vocabulary');
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
