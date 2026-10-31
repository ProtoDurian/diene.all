import { capturedEnvCommand, expectGreen } from './lib/helpers.ts';

const execBitSubject = `#!/usr/bin/env bash
set -euo pipefail

echo "hook-enforce-exec probe subject"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-enforce-exec-green',
      description: 'The generated dlint hook (exec-bits check) passes tracked shell scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-dlint --all-files', 'hook-enforce-exec');
      },
    },
    {
      name: 'mutation-hook-enforce-exec-caught',
      description: 'A focused sabotage must turn the hook-enforce-exec mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = 'probe-enforce-exec-subject.sh';
        await repo.write(target, execBitSubject);
        try {
          // exec-bits inspects only tracked scripts, so the fixture must be staged.
          const staged = await repo.exec(`chmod +x ${target} && git add ${target}`);
          if (staged.exitCode !== 0) {
            throw new Error(`could not stage the exec-bit fixture: ${staged.stderr || staged.stdout}`);
          }
          const sabotaged = await repo.exec(`chmod -x ${target}`);
          if (sabotaged.exitCode !== 0) {
            throw new Error(`could not clear the executable bit on ${target}: ${sabotaged.stderr || sabotaged.stdout}`);
          }
          const result = await repo.exec(
            capturedEnvCommand('nix develop .#ci -c pre-commit run a-dlint --all-files', 'hook-enforce-exec'),
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('hook-enforce-exec stayed green after sabotage');
          }
          if (!`${result.stdout}${result.stderr}`.includes(`'${target}' is tracked but not executable`)) {
            throw new Error(
              `hook-enforce-exec refused without naming the non-executable script: ${result.stdout}${result.stderr}`,
            );
          }
        } finally {
          await repo.exec(`git reset -q -- ${target}`);
          await repo.remove(target);
        }
      },
    },
  ],
};
