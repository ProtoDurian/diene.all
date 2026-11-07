import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const LEDGER = 'nix develop .#ci -c ./scripts/ci/test.sh meta coverage';
const MEMBER = 'packages/diene_core_utils';
const HELPER = `${MEMBER}/lib/test_helper.dart`;
const META_SUITE = `${MEMBER}/test/meta/empty_test.dart`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-testhelper-meta-coverage-ledger-green',
      description: 'without a TestHelper the meta coverage run no-ops and writes no meta ledger to upload',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, ['reports/meta'], async () => {
          await expectGreen(repo, LEDGER, 'testhelper-meta-coverage-ledger');
          if ((await repo.glob('reports/meta/**')).length !== 0) {
            throw new Error('testhelper-meta-coverage-ledger: the inactive meta tier wrote a ledger to upload');
          }
        });
      },
    },
    {
      name: 'mutation-testhelper-meta-coverage-ledger-caught',
      description: 'an added TestHelper whose meta suite never loads it is refused as an empty meta ledger',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [HELPER, META_SUITE, 'reports/meta'], async () => {
          await repo.write(HELPER, 'bool expectProbeSlug(String value) => value.isNotEmpty;\n');
          await repo.write(
            META_SUITE,
            "import 'package:test/test.dart';\n\n" +
              "void main() {\n  test('probe empty meta suite', () {\n    expect(1, 1);\n  });\n}\n",
          );
          await expectRedBecause(repo, LEDGER, 'testhelper-meta-coverage-ledger', [
            'meta coverage ledger contains no source files',
          ]);
        });
      },
    },
  ],
};
