import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';
import { assertScopedLcov } from './lib/lcov.ts';

const command = 'nix develop .#ci -c ./scripts/ci/test.sh int';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-coverage-green',
      description: 'Integration coverage is green: a no-op with no adapters, else complete and scoped to src/adapters.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-integration-coverage');
        if ((await repo.glob('src/adapters/**/*.ts')).length > 0) {
          await assertScopedLcov(repo, 'reports/integration/lcov.info', 'src/adapters/');
        }
      },
    },
    {
      name: 'mutation-bun-integration-coverage-caught',
      description: 'An adapter file no integration test covers turns the integration coverage ledger red.',
      kind: 'mutation',
      expectedImpact: ['bun-deadcode'],
      async run(repo: any) {
        await repo.write(
          'src/adapters/__probe_uncovered__.ts',
          'export class ProbeUncoveredAdapter {\n  value(): number {\n    return 1;\n  }\n}\n',
        );
        await repo.write(
          'tests/integration/__probe_unrelated__.test.ts',
          [
            "import { it } from 'bun:test';",
            "import 'should';",
            '',
            "it('passes without touching the adapter', () => {",
            '  // Arrange',
            '  const expected = 1;',
            '',
            '  // Act',
            '  const actual = 1;',
            '',
            '  // Assert',
            '  actual.should.equal(expected);',
            '});',
            '',
          ].join('\n'),
        );
        await repo.write(
          'src/index.ts',
          `${await repo.read('src/index.ts')}\nexport { ProbeUncoveredAdapter } from './adapters/__probe_uncovered__';\n`,
        );
        await expectBunRed(repo, command, 'bun-integration-coverage');
      },
    },
  ],
};
