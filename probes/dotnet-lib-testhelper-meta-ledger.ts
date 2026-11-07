import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';
import { expectRedBecause } from './lib/dotnet-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-testhelper-meta-ledger-green',
    description: 'The independent meta tier confines coverage to *.TestHelper assemblies at 100%.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c task test:meta:coverage', 'dotnet-lib-testhelper-meta-ledger');
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-testhelper-meta-ledger-caught',
    description: 'One uncovered public helper member turns the meta ledger red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.write(
        'TestHelper/MetaCoverageGap.cs',
        'namespace AtomiCloud.Diene.Otel.TestHelper;\n\npublic static class MetaCoverageGap\n{\n    public static int Uncovered() => 42;\n}\n',
      );
      await expectRedBecause(repo, 'nix develop .#ci -c task test:meta:coverage', 'dotnet-lib-testhelper-meta-ledger', [
        'line coverage is below the specified 100',
      ]);
    },
  },
});
