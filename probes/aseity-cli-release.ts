type ProbeRepo = {
  exec(
    command: string,
    options?: { timeoutMs?: number },
  ): Promise<{ exitCode: number; stdout: string; stderr: string }>;
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
};

const command =
  "nix develop .#releaser -c bash -lc 'bun install --frozen-lockfile && goreleaser check && ./scripts/release/publish.sh --snapshot && " +
  'test -x dist/aseity_bun-linux-x64-baseline/aseity && test -x dist/aseity_bun-linux-arm64/aseity && ' +
  'test -x dist/aseity_bun-darwin-arm64/aseity && test -f dist/aseity_bun-windows-x64-baseline/aseity.exe && ' +
  "ls dist/*.deb && test -f dist/scoop/aseity.json && test -f dist/homebrew/Casks/aseity.rb'";
const BUILDER = 'builder: bun\n';

async function release(repo: ProbeRepo) {
  const result = await repo.exec(command, { timeoutMs: 900_000 });
  return { ...result, output: `${result.stdout}\n${result.stderr}` };
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: [
      'if ! git remote get-url origin >/dev/null 2>&1; then git remote add origin https://github.com/AtomiCloud/diene.aseity.git; fi',
    ],
  },
  probes: [
    {
      name: 'baseline-aseity-cli-release-green',
      description:
        'The GoReleaser config checks, and a snapshot release compiles the Bun CLI for linux x64/arm64, macOS arm64 and Windows x64, smoke-runs it, and renders the deb, Scoop manifest and Homebrew cask without publishing.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        const result = await release(repo);
        if (result.exitCode !== 0)
          throw new Error(`CLI snapshot release failed on the healthy repo:\n${result.output}`);
      },
    },
    {
      name: 'mutation-aseity-cli-release-caught',
      description: 'A GoReleaser config naming an unknown builder turns the release check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = '.goreleaser.yaml';
        const source = await repo.read(path);
        if (!source.includes(BUILDER)) throw new Error(`${path} no longer uses the Bun builder`);
        await repo.write(path, source.replace(BUILDER, 'builder: bunx\n'));
        const result = await release(repo);
        if (result.exitCode === 0) throw new Error('CLI release stayed green with a broken GoReleaser config');
        if (!result.output.includes('bunx')) {
          throw new Error(`CLI release failed for another reason than the broken builder:\n${result.output}`);
        }
      },
    },
  ],
};
