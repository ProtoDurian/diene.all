import { plantUncoveredTestHelper } from './lib/go-library.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/local/test.sh meta true false';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-meta-coverage-green',
      description: 'The meta ledger covers the testhelper package at 100%.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-lib-meta-coverage');
      },
    },
    {
      name: 'mutation-go-lib-meta-coverage-caught',
      description: 'Uncovered TestHelper code turns the scoped meta ledger red.',
      kind: 'mutation',
      async run(repo: any) {
        await plantUncoveredTestHelper(repo);
        await expectRedWithDiagnostic(repo, gate, 'go-lib-meta-coverage', /meta coverage [0-9.]+% is below 100%/);
      },
    },
  ],
};
