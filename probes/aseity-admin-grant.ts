type ProbeRepo = {
  exec(
    command: string,
    options?: { timeoutMs?: number },
  ): Promise<{ exitCode: number; stdout: string; stderr: string }>;
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
};

const command =
  "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && bun test --timeout 120000 ./tests/e2e/admin/admin-cli.test.ts 2>&1'";
// The role name the tenant-approval check looks for.
const ADMIN_ROLE = "const ADMIN = 'admin';";
const GRANT_SCENARIO = '(fail) aseity admin grant (CLI, Postgres) > should make the first signed-up user an admin';

async function scenario(repo: ProbeRepo) {
  const result = await repo.exec(command, { timeoutMs: 600_000 });
  return { ...result, output: `${result.stdout}\n${result.stderr}` };
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-admin-grant-green',
      description:
        'Against real Postgres, `aseity admin grant <email>` gives a signed-up user the admin role, keeps their other roles, is idempotent, and refuses an email nobody signed up with.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        const result = await scenario(repo);
        if (result.exitCode !== 0 || !/\b3 pass\b/.test(result.output) || !/\b0 fail\b/.test(result.output)) {
          throw new Error(`admin grant scenario failed on the healthy repo:\n${result.output}`);
        }
      },
    },
    {
      name: 'mutation-aseity-admin-grant-caught',
      description: 'Granting a misspelled role leaves the user without admin rights, and the grant scenario goes red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = 'src/lib/admin/service.ts';
        const source = await repo.read(path);
        if (!source.includes(ADMIN_ROLE)) throw new Error(`${path} no longer names the admin role`);
        await repo.write(path, source.replace(ADMIN_ROLE, "const ADMIN = 'admins';"));
        const result = await scenario(repo);
        if (result.exitCode === 0) throw new Error('admin grant scenario stayed green with the wrong role');
        if (!result.output.includes(GRANT_SCENARIO)) {
          throw new Error(`admin grant scenario failed for another reason than the wrong role:\n${result.output}`);
        }
      },
    },
  ],
};
