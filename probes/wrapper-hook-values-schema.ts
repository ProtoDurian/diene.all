import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const command = 'nix develop .#ci -c pre-commit run a-wrapper-values-schema --all-files';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-hook-values-schema-green',
    description: 'The generator hook leaves the checked-in values schema unchanged.',
    async run(repo: any) {
      await expectGreen(repo, command, 'wrapper-hook-values-schema');
    },
  },
  mutation: {
    name: 'mutation-wrapper-hook-values-schema-caught',
    description: 'Changing a schema annotation without regenerating turns the generator hook red.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/values.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, {
          find: 'provider: digitalocean # @schema enum:[aws, oci, digitalocean]',
          replace: 'provider: digitalocean # @schema enum:[oci, digitalocean]',
        });
        await expectRed(repo, command, 'wrapper-hook-values-schema');
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
