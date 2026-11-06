import { expectGreen, expectRed } from './lib/helpers.ts';

// The padding before `;` is the sabotage; keep it.
const shfmtSubject = 'probe-fmt-shfmt.sh';
const shfmtSubjectBody = `#!/usr/bin/env bash
set -euo pipefail

if [ -n "$HOME" ]  ; then
  echo "fmt-shfmt probe subject"
fi
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-fmt-shfmt-green',
      description: 'The treefmt shfmt member passes on tracked shell scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix fmt --no-write-lock-file -- --ci --formatters shfmt', 'fmt-shfmt');
      },
    },
    {
      name: 'mutation-fmt-shfmt-caught',
      description: 'A focused sabotage must turn the fmt-shfmt mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(shfmtSubject, shfmtSubjectBody);
        try {
          const staged = await repo.exec(`git add ${shfmtSubject}`);
          if (staged.exitCode !== 0) {
            throw new Error(`could not stage the shfmt fixture: ${staged.stderr || staged.stdout}`);
          }
          await expectRed(repo, 'nix fmt --no-write-lock-file -- --ci --formatters shfmt', 'fmt-shfmt');
        } finally {
          await repo.exec(`git reset -q -- ${shfmtSubject}`);
          await repo.remove(shfmtSubject);
        }
      },
    },
  ],
};
