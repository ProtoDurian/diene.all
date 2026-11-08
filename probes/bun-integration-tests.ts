import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && task test:int'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-tests-green',
      description: 'The Bun integration tier stays green with zero adapters.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-integration-tests');
      },
    },
    {
      name: 'mutation-bun-integration-tests-caught',
      description: 'An adapter whose integration test asserts the wrong value turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['bun-integration-coverage'],
      async run(repo: any) {
        await repo.write(
          'src/adapters/__probe__.ts',
          'export function probeAdapterValue(): number {\n  return 1;\n}\n',
        );
        await repo.write(
          'tests/integration/__probe__.test.ts',
          [
            "import { describe, it } from 'bun:test';",
            "import 'should';",
            "import { probeAdapterValue } from '../../src/adapters/__probe__';",
            '',
            "describe('integration probe sabotage', () => {",
            "  it('asserts the wrong adapter value', () => {",
            '    probeAdapterValue().should.equal(2);',
            '  });',
            '});',
            '',
          ].join('\n'),
        );
        await expectBunRed(repo, command, 'bun-integration-tests');
      },
    },
  ],
};
