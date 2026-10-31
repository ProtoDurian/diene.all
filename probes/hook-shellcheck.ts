import { capturedEnvCommand, expectGreen } from './lib/helpers.ts';

// Each sourcing fixture is checked without the file it sources, as pre-commit batching does.
const sourceFixtureDir = 'probe-shellcheck-source';
const sourcedFixture = `${sourceFixtureDir}/init-state.sh`;
const repoRelativeFixture = `${sourceFixtureDir}/mark-done.sh`;
const scriptRelativeFixture = `${sourceFixtureDir}/next-file.sh`;
const findingFixture = `${sourceFixtureDir}/unquoted-expansion.sh`;
const findingBody = `#!/usr/bin/env bash
set -euo pipefail

echo $HOME/$UNQUOTED
`;

const sourcedBody = `#!/usr/bin/env bash
set -euo pipefail

STATE_VERSION=1
`;

const sourcingBody = (directive: string) => `#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=${directive}
source "$SCRIPT_DIR/init-state.sh"

echo "📝 state version \${STATE_VERSION}"
`;

async function removeSourceFixture(repo: any): Promise<void> {
  await repo.exec(`git rm -r -f -q --cached -- ${sourceFixtureDir}`);
  await repo.exec(`git clean -fdxq -- ${sourceFixtureDir}`);
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-shellcheck-green',
      description: 'The generated shellcheck hook passes on the untouched scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-shellcheck --all-files', 'hook-shellcheck');
      },
    },
    {
      name: 'baseline-hook-shellcheck-follows-sources',
      description:
        'The shellcheck hook follows a declared sourced script even when the sourced file is not in the same batch, for both repository-root-relative and script-relative source directives.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write(sourcedFixture, sourcedBody);
        await repo.write(repoRelativeFixture, sourcingBody(sourcedFixture));
        await repo.write(scriptRelativeFixture, sourcingBody('init-state.sh'));
        const staged = await repo.exec(`git add ${sourceFixtureDir}`);
        if (staged.exitCode !== 0) {
          throw new Error(`could not stage the source-following fixture: ${staged.stderr || staged.stdout}`);
        }
        try {
          await expectGreen(
            repo,
            `nix develop .#ci -c pre-commit run a-shellcheck --files ${repoRelativeFixture}`,
            'hook-shellcheck',
          );
          await expectGreen(
            repo,
            `nix develop .#ci -c pre-commit run a-shellcheck --files ${scriptRelativeFixture}`,
            'hook-shellcheck',
          );
        } finally {
          await removeSourceFixture(repo);
        }
      },
    },
    {
      name: 'mutation-hook-shellcheck-caught',
      description: 'A focused sabotage must turn the hook-shellcheck mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(findingFixture, findingBody);
        try {
          // --all-files reads only tracked files, so the fixture must be staged.
          const staged = await repo.exec(`git add ${findingFixture}`);
          if (staged.exitCode !== 0) {
            throw new Error(`could not stage the shellcheck fixture: ${staged.stderr || staged.stdout}`);
          }
          const result = await repo.exec(
            capturedEnvCommand('nix develop .#ci -c pre-commit run a-shellcheck --all-files', 'hook-shellcheck'),
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('hook-shellcheck stayed green after sabotage');
          }
          if (!`${result.stdout}${result.stderr}`.includes('SC2086')) {
            throw new Error(
              `hook-shellcheck refused without reporting the unquoted expansion: ${result.stdout}${result.stderr}`,
            );
          }
        } finally {
          await removeSourceFixture(repo);
        }
      },
    },
  ],
};
