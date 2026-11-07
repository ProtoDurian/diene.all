import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';
import { PACKAGE_VALIDATE, expectRedBecause, manifestVersion, packPackages } from './lib/dotnet-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-artifact-inventory-green',
    description: 'Both lockstep packages and both symbol packages exist at the committed version.',
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-artifact-inventory-pack');
      await expectGreen(repo, `${PACKAGE_VALIDATE} inventory`, 'dotnet-lib-artifact-inventory');
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-artifact-inventory-caught',
    description: 'Omitting exactly one required symbols artifact turns inventory validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-artifact-inventory-mutation-pack');
      await repo.exec(
        'rm "$(find artifacts/package -maxdepth 1 -name \'AtomiCloud.Diene.Problems.TestHelper.*.snupkg\' -print -quit)"',
      );
      await expectRedBecause(repo, `${PACKAGE_VALIDATE} inventory`, 'dotnet-lib-artifact-inventory', [
        `❌ Missing AtomiCloud.Diene.Note.TestHelper.${await manifestVersion(repo)}.snupkg`,
      ]);
    },
  },
});
