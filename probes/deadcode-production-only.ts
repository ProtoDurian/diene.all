import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const DEADCODE = 'nix develop .#ci -c ./scripts/ci/deadcode.sh';
const MEMBER = 'packages/diene_dart_lib';
const LIB_FIXTURE = `${MEMBER}/lib/src/probe_production_only.dart`;
const TEST_FIXTURE = `${MEMBER}/test/unit/probe_production_only_test.dart`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline'] },
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
      description: 'a file referenced only by a test passes the whole-package view and reddens the production view',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [LIB_FIXTURE, TEST_FIXTURE], async () => {
          await repo.write(LIB_FIXTURE, 'int probeProductionOnly() => 1;\n');
          await repo.write(
            TEST_FIXTURE,
            "import 'package:diene_dart_lib/src/probe_production_only.dart';\n" +
              "import 'package:test/test.dart';\n\n" +
              "void main() {\n  test('probe production only', () {\n    expect(probeProductionOnly(), 1);\n  });\n}\n",
          );
          await expectRedBecause(repo, DEADCODE, 'deadcode-production-only', [
            'Production dead-code pass',
            'probe_production_only.dart',
          ]);
        });
      },
    },
  ],
};
