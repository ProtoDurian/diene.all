import { expectBunGreen } from './lib/bun-command.ts';
import { expectRedBecause } from './lib/helpers.ts';

interface ProbeRepo {
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
}

const command =
  "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && bun test --config=bunfig.unit.toml tests/unit/architecture/worker-safe.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-worker-safe-green',
      description: 'Worker code uses no Bun-only API and wrangler bundles it with no Bun import.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectBunGreen(repo, command, 'aseity-worker-safe');
      },
    },
    {
      name: 'mutation-aseity-worker-safe-caught',
      description: 'A Bun.version call in a domain module the Worker reaches turns the worker-safe check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = 'src/lib/notes/service.ts';
        const source = await repo.read(path);
        if (!source.includes('const LIST_KEY')) throw new Error(`${path} no longer contains the sabotage target`);
        await repo.write(path, source.replace('const LIST_KEY', 'console.log(Bun.version);\n\nconst LIST_KEY'));
        await expectRedBecause(
          repo,
          command,
          'aseity-worker-safe',
          ['should not use the Bun global in any module the Worker reaches'],
          { timeoutMs: 600_000 },
        );
      },
    },
  ],
};
