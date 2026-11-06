import { expectBunGreen } from './lib/bun-command.ts';
import { expectRedBecause } from './lib/helpers.ts';

interface ProbeRepo {
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
}

const command =
  "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && bun test --config=bunfig.int.toml tests/integration/tenancy/rls.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-rls-green',
      description: "On real Postgres a second tenant cannot read, change or plant the first tenant's rows.",
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectBunGreen(repo, command, 'aseity-rls');
      },
    },
    {
      name: 'mutation-aseity-rls-caught',
      description: 'A notes policy that admits every row turns the row-level security check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = 'db/migrations/0003_notes.sql';
        const source = await repo.read(path);
        if (!source.includes('USING (tenant_id = app_current_tenant())'))
          throw new Error(`${path} no longer contains the sabotage target`);
        await repo.write(path, source.replace('USING (tenant_id = app_current_tenant())', 'USING (true)'));
        await expectRedBecause(repo, command, 'aseity-rls', ['should hide notes rows from another tenant'], {
          timeoutMs: 600_000,
        });
      },
    },
  ],
};
