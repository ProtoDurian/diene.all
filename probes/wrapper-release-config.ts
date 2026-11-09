import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const command = 'nix develop .#ci -c ./probes/checks/release-lint.sh parse';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-release-config-green',
    description: 'release.yaml parses and is a valid registry releaser configuration.',
    async run(repo: any) {
      await expectGreen(repo, command, 'wrapper-release-config');
    },
  },
  mutation: {
    name: 'mutation-wrapper-release-config-caught',
    description: 'Malformed release.yaml is rejected.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'release.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, { find: 'types:\n', replace: 'types: [\n' });
        await expectRed(repo, command, 'wrapper-release-config');
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
