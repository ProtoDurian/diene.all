import { expectBunGreen } from './lib/bun-command.ts';
import { expectRedBecause } from './lib/helpers.ts';

interface ProbeRepo {
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
}

const command =
  "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && bun test --config=bunfig.int.toml --timeout 120000 tests/integration/jobs/runner.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-job-runner-green',
      description:
        'A job claimed by one runner is never handed to a second, concurrent runner, and a fork holds outside-effect jobs.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectBunGreen(repo, command, 'aseity-job-runner');
      },
    },
    {
      name: 'mutation-aseity-job-runner-caught',
      description:
        'A claim without FOR UPDATE SKIP LOCKED hands a held job to a second runner and turns the check red.',
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
          ['should never hand a job another runner holds to a second runner'],
          { timeoutMs: 600_000 },
        );
      },
    },
  ],
};
