import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-values-schema-green',
    description: 'The generated schema accepts every committed stacked values path.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh schema', 'wrapper-values-schema');
    },
  },
  mutation: {
    name: 'mutation-wrapper-values-schema-caught',
    description: 'An unsupported provider in a committed overlay is rejected by the generated schema.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/values.lapras.yaml';
      const original = await repo.read(path);
      try {
        await repo.write(path, `${original}\ngateway:\n  provider: unsupported\n`);
        await expectRedBecause(
          repo,
          'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh schema',
          'wrapper-values-schema',
          ['schema rejected the stack', "at '/gateway/provider'"],
        );
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
