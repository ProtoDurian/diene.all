import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const DEADCODE = 'nix develop .#ci -c ./scripts/ci/deadcode.sh';
const MEMBER = 'packages/diene_api_engine';
const LIB_FIXTURE = `${MEMBER}/lib/src/probe_production_only.dart`;
const TEST_FIXTURE = `${MEMBER}/test/unit/probe_production_only_test.dart`;
const BARREL = `${MEMBER}/lib/diene_api_engine.dart`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
  probes: [
    {
      name: 'baseline-deadcode-production-only-green',
      description: 'the production-only view of the test-free shipped surface is clean',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, DEADCODE, 'deadcode-production-only');
      },
    },
    {
      name: 'mutation-deadcode-production-only-caught',
      description: 'a barrel export used only by a test passes the whole-package view and reddens the production view',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [BARREL, LIB_FIXTURE, TEST_FIXTURE], async () => {
          await repo.write(LIB_FIXTURE, 'int probeProductionOnly() => 1;\n');
          await repo.write(BARREL, `${await repo.read(BARREL)}\nexport 'src/probe_production_only.dart';\n`);
          await repo.write(
            TEST_FIXTURE,
            "import 'package:diene_api_engine/diene_api_engine.dart';\n" +
              "import 'package:flutter_test/flutter_test.dart';\n\n" +
              "void main() {\n  test('probe production only', () {\n    expect(probeProductionOnly(), 1);\n  });\n}\n",
          );
          await expectRedBecause(repo, DEADCODE, 'deadcode-production-only', [
            'Production dead-code pass',
            'unused function probeProductionOnly',
          ]);
        });
      },
    },
  ],
};
