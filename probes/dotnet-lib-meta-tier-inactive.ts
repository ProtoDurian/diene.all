import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-meta-tier-inactive-green',
    description: 'With no TestHelper project the meta tier self-deactivates and produces no coverage artifact.',
    async run(repo: any) {
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c 'test -z "$(find . -maxdepth 2 -type f -path "*/TestHelper*.csproj" -print -quit)"'`,
        'dotnet-lib-meta-tier-inactive',
      );
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c 'task test:meta:coverage | rg -Fq "meta tier is inactive"'`,
        'dotnet-lib-meta-tier-inactive',
        600000,
      );
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c 'test ! -e TestResults/meta/coverage/coverage.cobertura.xml'`,
        'dotnet-lib-meta-tier-inactive',
      );
    },
  },
});
