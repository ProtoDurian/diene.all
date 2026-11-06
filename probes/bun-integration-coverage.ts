import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = 'nix develop .#ci -c ./scripts/ci/test.sh int';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-coverage-green',
      description: 'With zero adapters the integration tier is green and emits no coverage artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-integration-coverage');
        if ((await repo.glob('reports/integration/lcov.info')).length !== 0) {
          throw new Error('an adapter-free integration tier must not emit a coverage artifact');
        }
      },
    },
    {
      name: 'mutation-bun-integration-coverage-caught',
      description: 'An uncovered adapter source file turns the integration coverage ledger red.',
      kind: 'mutation',
      expectedImpact: ['bun-deadcode', 'bun-integration-tests'],
      async run(repo: any) {
        await repo.write(
          'src/adapters/__probe_uncovered__.ts',
          'export function probeAdapterUncovered(): number {\n  return 1;\n}\n',
        );
        await repo.write(
          'src/index.ts',
          `${await repo.read('src/index.ts')}\nexport { probeAdapterUncovered } from './adapters/__probe_uncovered__';\n`,
        );
        await expectBunRed(repo, command, 'bun-integration-coverage');
      },
    },
  ],
};
