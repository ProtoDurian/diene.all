import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';
import { expectRedBecause } from './lib/dotnet-package.ts';

// Version 1.0.0 skips the baseline (it is the baseline), so pack 1.0.1 to arm the gate.
const packAgainstPublishedBaseline =
  'rm -rf artifacts/api-candidate && mkdir -p artifacts/api-candidate && dotnet pack Lib/Lib.csproj -c Release -p:Version=1.0.1 --output artifacts/api-candidate';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-api-compatibility-green',
    description: 'PackageValidation accepts the unchanged public API against the published 1.0.0 package.',
    async run(repo: any) {
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c '${packAgainstPublishedBaseline}'`,
        'dotnet-lib-api-compatibility',
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-api-compatibility-caught',
    description:
      'Removing a public member the published 1.0.0 package ships, and nothing in Lib reads, turns PackageValidation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('Lib/IProblemExporter.cs', {
        find: '\n    /// <summary>Exports every registered descriptor.</summary>\n    IReadOnlyList<ProblemExport> ExportAll();',
        replace: '',
      });
      await expectRedBecause(
        repo,
        `nix develop .#ci -c bash -c '${packAgainstPublishedBaseline}'`,
        'dotnet-lib-api-compatibility',
        ['CP0002'],
      );
    },
  },
});
