import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const command = 'nix develop .#ci -c ./probes/checks/release-lint.sh types';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-release-lint-types-green',
    description: 'The registry releaser lint-commit accepts exactly the types release.yaml declares.',
    async run(repo: any) {
      await expectGreen(repo, command, 'wrapper-release-lint-types');
    },
  },
  mutation: {
    name: 'mutation-wrapper-release-lint-types-caught',
    description: 'A commit-msg hook linting against a config other than release.yaml diverges from the declared types.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'nix/pre-commit.nix';
      const original = await repo.read(path);
      try {
        await repo.patch(path, {
          find: 'lint-commit -c release.yaml"',
          replace: 'lint-commit -c .release.legacy.yaml"',
        });
        await expectRed(repo, command, 'wrapper-release-lint-types');
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
