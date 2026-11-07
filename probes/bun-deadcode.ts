import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pre-commit run a-deadcode --all-files'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-deadcode-green',
      description: 'The strict repository Knip hook accepts the complete source and tests.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-deadcode');
      },
    },
    {
      name: 'mutation-bun-deadcode-caught',
      description: 'An unused library module or exported member turns the repository Knip hook red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const entries: string[] = await repo.glob('src/*.ts');
        const entrySource = (await Promise.all(entries.map(entry => repo.read(entry)))).join('\n');
        const internal = (await repo.glob('src/lib/**/*.ts')).sort().find((candidate: string) => {
          const modulePath = `./${candidate.replace(/^src\//, '').replace(/\.ts$/, '')}`;
          return !['', '.js'].some(ext => entrySource.includes(`export * from '${modulePath}${ext}'`));
        });
        const path = internal ?? 'src/lib/__probe_dead__.ts';
        const prior = internal ? await repo.read(path) : '';
        await repo.write(path, `${prior}\nexport const probeDead = 1;\n`);
        await expectBunRed(repo, command, 'bun-deadcode');
      },
    },
  ],
};
