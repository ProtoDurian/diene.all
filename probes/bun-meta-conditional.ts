import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';
import { assertScopedLcov } from './lib/lcov.ts';

const command = 'nix develop .#ci -c ./scripts/ci/test.sh meta';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-meta-conditional-active-green',
      description: 'The shipped TestHelper activates the meta tier: green, with a ledger scoped to src/test-helper.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-meta-conditional');
        await assertScopedLcov(repo, 'reports/meta/lcov.info', 'src/test-helper/');
      },
    },
    {
      name: 'mutation-bun-meta-conditional-caught',
      description: 'An activated TestHelper meta test with a failing assertion must redden the meta tier.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write('src/test-helper/probe.ts', 'export function probeMetaValue(): number {\n  return 1;\n}\n');
        await repo.write(
          'tests/meta/conditional.test.ts',
          [
            "import { expect, test } from 'bun:test';",
            "import { probeMetaValue } from '../../src/test-helper/probe';",
            '',
            "test('meta conditional sabotage fails', () => {",
            '  expect(probeMetaValue()).toBe(2);',
            '});',
            '',
          ].join('\n'),
        );
        await expectBunRed(repo, command, 'bun-meta-conditional');
      },
    },
    {
      name: 'mutation-bun-meta-coverage-caught',
      description: 'An untested TestHelper module turns the meta coverage ledger red.',
      kind: 'mutation',
      expectedImpact: ['bun-deadcode'],
      async run(repo: any) {
        await repo.write(
          'src/test-helper/__probe_uncovered__.ts',
          'export function probeHelperUncovered(): number {\n  return 1;\n}\n',
        );
        await expectBunRed(repo, command, 'bun-meta-conditional');
      },
    },
  ],
};
