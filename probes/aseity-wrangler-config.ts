import { expectGreen, expectRedBecause } from './lib/helpers.ts';

type ProbeRepo = {
  exec(
    command: string,
    options?: { timeoutMs?: number },
  ): Promise<{ exitCode: number; stdout: string; stderr: string }>;
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
};

const command = "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && ./scripts/validate/wrangler.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-wrangler-config-green',
      description: 'wrangler.jsonc dry-run deploys, and its bindings and vars match infra/tofu and the sealed keys.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectGreen(repo, command, 'aseity-wrangler-config');
      },
    },
    {
      name: 'mutation-aseity-wrangler-config-caught',
      description: 'Renaming the HYPERDRIVE binding turns the contract check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = 'wrangler.jsonc';
        const config = await repo.read(path);
        if (!config.includes('"binding": "HYPERDRIVE"'))
          throw new Error('aseity-wrangler-config: no HYPERDRIVE binding to rename');
        await repo.write(path, config.replace('"binding": "HYPERDRIVE"', '"binding": "DATABASE"'));
        await expectRedBecause(
          repo,
          command,
          'aseity-wrangler-config',
          ['the only hyperdrive binding must be HYPERDRIVE (found [DATABASE])'],
          { forbidden: ['wrangler.jsonc matches infra/tofu'] },
        );
      },
    },
  ],
};
