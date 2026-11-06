import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && task test:int'";
const mixinCall = 'mixin: () => this.traceContext.fields(),';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-tests-green',
      description: 'The Bun integration tier proves the OTel adapters in-process with no collector.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-integration-tests');
      },
    },
    {
      name: 'mutation-bun-integration-tests-caught',
      description: 'A pino logger that drops the trace context turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const paths = await repo.glob('src/adapters/**/*.ts');
        for (const path of paths) {
          const source = await repo.read(path);
          if (source.includes(mixinCall)) {
            await repo.write(path, source.replace(mixinCall, 'mixin: () => ({}),'));
            await expectBunRed(repo, command, 'bun-integration-tests');
            return;
          }
        }
        throw new Error('no structural pino adapter target found');
      },
    },
  ],
};
