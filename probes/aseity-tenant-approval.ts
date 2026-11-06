type ProbeRepo = {
  exec(
    command: string,
    options?: { timeoutMs?: number },
  ): Promise<{ exitCode: number; stdout: string; stderr: string }>;
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
  glob(pattern: string): Promise<string[]>;
};

const SCENARIO = 'should keep a new tenant pending until an admin approves it';
const command = `nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && bun test --config=bunfig.int.toml --timeout 120000 tests/integration/auth/flow.test.ts -t "${SCENARIO}" 2>&1'`;
const APPROVAL_CHECK = /^\s*if \(status !== 'approved'\) return Err\(new TenantNotApproved\(tenantId, status\)\);\n/m;

async function scenario(repo: ProbeRepo) {
  const result = await repo.exec(command, { timeoutMs: 600_000 });
  return { ...result, output: `${result.stdout}\n${result.stderr}` };
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-tenant-approval-green',
      description:
        'Against real Postgres, a new tenant is pending: its member gets a 403 tenant_pending Problem, the owner cannot self-approve, and after an admin approves it the same member is let through.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        const result = await scenario(repo);
        if (result.exitCode !== 0 || !/\b1 pass\b/.test(result.output) || !/\b0 fail\b/.test(result.output)) {
          throw new Error(`tenant approval scenario failed on the healthy repo:\n${result.output}`);
        }
      },
    },
    {
      name: 'mutation-aseity-tenant-approval-caught',
      description:
        'Deleting the approval check lets a pending tenant act, and the scenario goes red on the pending request.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = 'src/lib/auth/approval.ts';
        const source = await repo.read(path);
        if (!APPROVAL_CHECK.test(source)) throw new Error(`${path} no longer holds the approval check`);
        await repo.write(path, source.replace(APPROVAL_CHECK, ''));
        const result = await scenario(repo);
        if (result.exitCode === 0) throw new Error('tenant approval scenario stayed green without the approval check');
        if (!result.output.includes('expected 200 to be 403')) {
          throw new Error(`scenario failed for another reason than the admitted pending tenant:\n${result.output}`);
        }
      },
    },
  ],
};
