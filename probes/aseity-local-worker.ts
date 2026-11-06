import { expectBunGreen } from './lib/bun-command.ts';
import { expectRedBecause } from './lib/helpers.ts';

interface ProbeRepo {
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
}

const command =
  "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && bun test --config=bunfig.e2e.toml tests/e2e/worker/local-worker.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-local-worker-green',
      description: 'wrangler dev serves health and a tenant notes flow from local workerd against Postgres.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectBunGreen(repo, command, 'aseity-local-worker');
      },
    },
    {
      name: 'mutation-aseity-local-worker-caught',
      description:
        'Renaming the Hyperdrive binding in wrangler.jsonc breaks the database path and turns the check red.',
      kind: 'mutation',
      // The same rename is what the wrangler config check refuses.
      expectedImpact: ['aseity-wrangler-config'],
      async run(repo: ProbeRepo) {
        const path = 'wrangler.jsonc';
        const source = await repo.read(path);
        if (!source.includes('"binding": "HYPERDRIVE"'))
          throw new Error(`${path} no longer contains the sabotage target`);
        await repo.write(path, source.replace('"binding": "HYPERDRIVE"', '"binding": "DATABASE"'));
        await expectRedBecause(
          repo,
          command,
          'aseity-local-worker',
          ['should serve health from the Hyperdrive-bound database'],
          { timeoutMs: 600_000 },
        );
      },
    },
  ],
};
