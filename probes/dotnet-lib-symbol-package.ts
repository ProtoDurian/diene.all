import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';
import { PACKAGE_VALIDATE, expectRedBecause, packPackages } from './lib/dotnet-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-symbol-package-green',
    description: 'Each snupkg independently contains a portable PDB and matching nuspec.',
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-symbol-package-pack');
      await expectGreen(repo, `${PACKAGE_VALIDATE} symbols`, 'dotnet-lib-symbol-package');
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-symbol-package-caught',
    description: 'Replacing one symbols package with its PDB-free nupkg turns symbol validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-symbol-package-mutation-pack');
      await repo.exec(
        'package="$(find artifacts/package -maxdepth 1 -name \'AtomiCloud.Diene.CoreUtils.*.nupkg\' -print -quit)"; symbols="${package%.nupkg}.snupkg"; cp "${package}" "${symbols}"',
      );
      await expectRedBecause(repo, `${PACKAGE_VALIDATE} symbols`, 'dotnet-lib-symbol-package', [
        'symbols package contains no portable PDB',
      ]);
    },
  },
});
