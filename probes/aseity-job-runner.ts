import { expectBunGreen } from './lib/bun-command.ts';
import { expectRedBecause } from './lib/helpers.ts';

interface ProbeRepo {
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
}

const command =
  "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && bun test --config=bunfig.int.toml tests/integration/jobs/runner.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-job-runner-green',
      description: 'Two concurrent runners run each job exactly once, and a fork holds outside-effect jobs.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectBunGreen(repo, command, 'aseity-job-runner');
      },
    },
    {
      name: 'mutation-aseity-job-runner-caught',
      description:
        'A claim without FOR UPDATE SKIP LOCKED lets both runners take the same job and turns the check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = 'src/adapters/data/jobs/repo.ts';
        const source = await repo.read(path);
        if (!source.includes('  FOR UPDATE SKIP LOCKED\n'))
          throw new Error(`${path} no longer contains the sabotage target`);
        await repo.write(path, source.replace('  FOR UPDATE SKIP LOCKED\n', ''));
        await expectRedBecause(
          repo,
          command,
          'aseity-job-runner',
          ['should run each job exactly once under two concurrent runners'],
          { timeoutMs: 600_000 },
        );
      },
    },
  ],
};
