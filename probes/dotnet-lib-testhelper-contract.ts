import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/dotnet.ts';

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
      await repo.patch('TestHelper/Note/NoteAssertions.cs', {
        find: 'if (!string.Equals(actual, expected, StringComparison.Ordinal))',
        replace: 'if (actual is null)',
      });
      await expectRed(repo, UNIT, 'dotnet-lib-testhelper-contract');
    },
  },
});
