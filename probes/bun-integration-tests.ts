import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && task test:int'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-integration-tests-green',
      description: 'The empty Bun integration tier (no adapters, no tests) is a green no-op.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'bun-integration-tests');
      },
    },
    {
      name: 'mutation-bun-integration-tests-caught',
      description: 'A paired adapter and failing integration test turn the tier red, so the tier really runs.',
      kind: 'mutation',
      expectedImpact: ['bun-integration-coverage', 'bun-deadcode'],
      async run(repo: any) {
        await repo.write(
          'src/adapters/__probe_red__.ts',
          'export class ProbeRedAdapter {\n  value(): number {\n    return 1;\n  }\n}\n',
        );
        await repo.write(
          'tests/integration/__probe_red__.test.ts',
          [
            "import { it } from 'bun:test';",
            "import 'should';",
            "import { ProbeRedAdapter } from '../../src/adapters/__probe_red__';",
            '',
            "it('fails on purpose', () => {",
            '  // Arrange',
            '  const adapter = new ProbeRedAdapter();',
            '',
            '  // Act',
            '  const actual = adapter.value();',
            '',
            '  // Assert',
            '  actual.should.equal(2);',
            '});',
            '',
          ].join('\n'),
        );
        await expectBunRed(repo, command, 'bun-integration-tests');
      },
    },
  ],
};
