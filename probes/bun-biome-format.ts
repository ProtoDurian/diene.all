import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = "nix develop .#ci -c bash -lc 'nix fmt --no-write-lock-file -- --ci --formatters biome'";
const treefmtImpact = [
  'precommit-treefmt-actionlint',
  'precommit-treefmt-nixfmt',
  'precommit-treefmt-prettier',
  'precommit-treefmt-shfmt',
];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  // One install for the matrix; drop the hooks the shell adds, they block fixture commits.
  setup: {
    pre: [
      'nix develop .#ci -c bun install --frozen-lockfile',
      'rm -f .git/hooks/pre-commit .git/hooks/commit-msg .pre-commit-config.yaml',
    ],
  },
  probes: [
    {
      name: 'baseline-bun-biome-format-green',
      description: 'The treefmt Biome member accepts every TypeScript, JavaScript and JSON file.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'bun-biome-format');
      },
    },
    {
      name: 'mutation-bun-biome-format-caught',
      description: 'A mis-formatted TypeScript file must be refused as an unformatted file, not merely fail.',
      kind: 'mutation',
      expectedImpact: treefmtImpact,
      async run(repo: any) {
        const path = (await repo.glob('src/lib/**/*.ts')).sort()[0];
        if (!path) throw new Error('no TypeScript library source found');
        const original = await repo.read(path);
        try {
          await repo.write(path, `${original}\n\n`);
          await expectRedBecause(repo, gate, 'bun-biome-format', [path, 'unexpected changes detected']);
        } finally {
          // treefmt rewrites in place even under --ci, so the restore is load-bearing.
          await repo.write(path, original);
        }
      },
    },
    {
      name: 'mutation-bun-biome-format-no-install',
      description: 'Without installed dependencies the Biome member must fail and point at the setup task.',
      kind: 'mutation',
      expectedImpact: treefmtImpact,
      async run(repo: any) {
        const removed = await repo.exec('rm -rf node_modules');
        if (removed.exitCode !== 0) throw new Error(`failed to remove node_modules: ${removed.stderr}`);
        await expectRedBecause(repo, gate, 'bun-biome-format', ['run the setup task first']);
        const absent = await repo.exec('test ! -e node_modules');
        if (absent.exitCode !== 0) throw new Error('the Biome member installed dependencies itself');
      },
    },
  ],
};
