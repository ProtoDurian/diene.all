import { stripExportDoc } from './lib/go-library.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-export-docs.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-export-docs-green',
      description: 'Every exported symbol carries a doc comment.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-lib-export-docs');
      },
    },
    {
      name: 'mutation-go-lib-export-docs-caught',
      description: 'Stripping one export doc comment turns the export-doc lint red.',
      kind: 'mutation',
      async run(repo: any) {
        await stripExportDoc(repo);
        await expectRedWithDiagnostic(
          repo,
          gate,
          'go-lib-export-docs',
          /exported: exported (?:function|type|method) [A-Za-z0-9_.]+ should have comment/,
        );
      },
    },
  ],
};
