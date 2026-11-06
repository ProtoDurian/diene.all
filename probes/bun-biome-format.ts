import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const gate = "nix develop .#ci -c bash -lc 'nix fmt --no-write-lock-file -- --ci --formatters biome'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
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
      expectedImpact: [
        'precommit-treefmt-actionlint',
        'precommit-treefmt-nixfmt',
        'precommit-treefmt-prettier',
        'precommit-treefmt-shfmt',
      ],
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
  ],
};
