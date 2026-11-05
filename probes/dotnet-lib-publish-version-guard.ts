import { defineGate } from './lib/definition.ts';
import { expectGreen } from './lib/dotnet.ts';
import { expectRedBecause } from './lib/dotnet-package.ts';

const GUARD = 'nix develop .#ci -c ./scripts/validate/dotnet-publish.sh';

async function manifestVersion(repo: any): Promise<string> {
  const version = /<Version>([^<]+)<\/Version>/.exec(await repo.read('Version.props'))?.[1];
  if (!version) {
    throw new Error('Version.props declares no <Version>');
  }
  return version;
}

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-publish-version-guard-green',
    description: 'The publish guard accepts a tag matching the committed Version.props value.',
    async run(repo: any) {
      await expectGreen(
        repo,
        `GITHUB_REF_NAME=v${await manifestVersion(repo)} ${GUARD}`,
        'dotnet-lib-publish-version-guard',
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-publish-version-guard-caught',
    description: 'A tag and manifest version mismatch exits red before any publish operation.',
    expectedImpact: [],
    async run(repo: any) {
      await expectRedBecause(
        repo,
        `GITHUB_REF_NAME=v${await manifestVersion(repo)}-probe-drift ${GUARD}`,
        'dotnet-lib-publish-version-guard',
        ['!= tag version'],
      );
    },
  },
});
