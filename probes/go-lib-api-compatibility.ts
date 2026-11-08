import { renameExportedFunction } from './lib/go-library.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-api-compat.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-api-compatibility-green',
      description: 'gorelease accepts the public surface against the sealed v1 baseline.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-lib-api-compatibility');
      },
    },
    {
      name: 'mutation-go-lib-api-compatibility-caught',
      description: 'Renaming an exported function without a major version turns gorelease red.',
      kind: 'mutation',
      async run(repo: any) {
        const renamed = await renameExportedFunction(repo);
        if (!renamed) {
          throw new Error('no exported function renamed');
        }
        await expectRedWithDiagnostic(repo, gate, 'go-lib-api-compatibility', /## incompatible changes[\s\S]*removed/);
      },
    },
  ],
};
