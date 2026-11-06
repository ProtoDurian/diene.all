type ProbeRepo = {
  exec(
    command: string,
    options?: { timeoutMs?: number },
  ): Promise<{ exitCode: number; stdout: string; stderr: string }>;
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
};

const command =
  "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && bun test --timeout 120000 ./tests/e2e/fork/fork-cli.test.ts 2>&1'";
const SIGN_OUT = `const sessionsDeleted = await this.count(client, 'DELETE FROM "session"');`;
const SANITIZE_SCENARIO = '(fail) aseity fork (CLI, Postgres + MinIO) > should fork a copy that is signed out';

async function scenario(repo: ProbeRepo) {
  const result = await repo.exec(command, { timeoutMs: 900_000 });
  return { ...result, output: `${result.stdout}\n${result.stderr}` };
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-fork-green',
      description:
        'Against Postgres and MinIO containers, `aseity fork create` copies the database rows and bucket objects, signs everyone out, disables API keys, rotates stored secrets, holds outside-effect jobs and marks fork_meta; `fork list` shows the fork and `fork delete` removes both copies.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        const result = await scenario(repo);
        if (result.exitCode !== 0 || !/\b5 pass\b/.test(result.output) || !/\b0 fail\b/.test(result.output)) {
          throw new Error(`fork scenario failed on the healthy repo:\n${result.output}`);
        }
      },
    },
    {
      name: 'mutation-aseity-fork-caught',
      description:
        'A sanitizer that skips signing everyone out (while still reporting the count) leaves live sessions in the fork, and the fork scenario goes red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = 'src/adapters/fork/pg-fork-sanitizer.ts';
        const source = await repo.read(path);
        if (!source.includes(SIGN_OUT)) throw new Error(`${path} no longer holds the sign-out step`);
        await repo.write(path, source.replace(SIGN_OUT, 'const sessionsDeleted = 2;'));
        const result = await scenario(repo);
        if (result.exitCode === 0) throw new Error('fork scenario stayed green with sessions left in the fork');
        if (!result.output.includes(SANITIZE_SCENARIO)) {
          throw new Error(`fork scenario failed for another reason than the kept sessions:\n${result.output}`);
        }
      },
    },
  ],
};
