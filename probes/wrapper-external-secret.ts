import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-external-secret-green',
    description: 'Folder-derived ExternalSecret prefixes produce collision-proof service and shared keys.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh secret',
        'wrapper-external-secret',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-external-secret-caught',
    description: 'A hand-written key mapping in the ExternalSecret template is detected.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/templates/externalsecret.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, {
          find: '  dataFrom:\n',
          replace:
            '  data:\n    - secretKey: HANDWRITTEN\n      remoteRef:\n        key: /wrapper/HANDWRITTEN\n  dataFrom:\n',
        });
        await expectRedBecause(
          repo,
          'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh secret',
          'wrapper-external-secret',
          ['ExternalSecret declares hand-written key mappings (spec.data)'],
        );
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
