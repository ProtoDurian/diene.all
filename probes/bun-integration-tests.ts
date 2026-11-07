import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && task test:int'";
const parseCall = 'return parseYaml(text);';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-tests-green',
      description: 'The Bun integration tier proves the YAML config source against real files.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-integration-tests');
      },
    },
    {
      name: 'mutation-bun-integration-tests-caught',
      description: 'A YAML adapter that ignores the file content turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['bun-integration-coverage'],
      async run(repo: any) {
        const paths = await repo.glob('src/adapters/**/*.ts');
        for (const path of paths) {
          const source = await repo.read(path);
          if (source.includes(parseCall)) {
            await repo.write(path, source.replace(parseCall, 'return {};'));
            await expectBunRed(repo, command, 'bun-integration-tests');
            return;
          }
        }
        throw new Error('no structural YAML adapter target found');
      },
    },
  ],
};
