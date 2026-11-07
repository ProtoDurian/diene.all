import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';
import { expectRedBecause } from './lib/dotnet-package.ts';

const UNIT_COVERAGE = 'nix develop .#ci -c task test:unit:coverage';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-coverage-ledger-green',
    description: 'The unit ledger holds the shipped AtomiCloud.Diene.Otel assembly at 100%.',
    async run(repo: any) {
      await expectGreen(repo, UNIT_COVERAGE, 'dotnet-lib-coverage-ledger');
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-coverage-ledger-caught',
    description: 'One uncovered member in the shipped namespace reddens the unit ledger.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.write(
        'Lib/ShippedCoverageGap.cs',
        'namespace AtomiCloud.Diene.Otel;\n\npublic static class ShippedCoverageGap\n{\n    public static int Uncovered() => 42;\n}\n',
      );
      await expectRedBecause(repo, UNIT_COVERAGE, 'dotnet-lib-coverage-ledger', [
        'line coverage is below the specified 100',
      ]);
    },
  },
});
