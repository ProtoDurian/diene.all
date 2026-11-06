import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';
import { expectRedBecause } from './lib/dotnet-package.ts';

const UNIT = 'nix develop .#ci -c task test:unit';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-testhelper-contract-green',
    description: 'The repo unit tests consume the TestHelper assertions and pass.',
    async run(repo: any) {
      await expectGreen(repo, UNIT, 'dotnet-lib-testhelper-contract');
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-testhelper-contract-caught',
    description: 'A TestHelper assertion that never rejects reddens the unit tier.',
    expectedImpact: ['dotnet-lib-testhelper-meta-ledger'],
    async run(repo: any) {
      await repo.patch('TestHelper/SeamAssertions.cs', {
        find: '.ForCondition(error.Seam == seam && string.Equals(error.Id, id, StringComparison.Ordinal))',
        replace: '.ForCondition(true)',
      });
      await expectRedBecause(repo, UNIT, 'dotnet-lib-testhelper-contract', ['BeSeamErr_should_fail_on_a_different_id']);
    },
  },
});
