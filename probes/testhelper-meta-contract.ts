import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const MEMBER = 'packages/diene_core_utils';
const HELPER = `${MEMBER}/lib/test_helper.dart`;
const META_SUITE = `${MEMBER}/test/meta/test_helper_test.dart`;

// This package has no TestHelper: the archive must not ship one and the meta tier must no-op.
const NO_HELPER =
  "nix develop .#ci -c bash -c 'set -euo pipefail; " +
  `(cd ${MEMBER}; listing=$(dart pub publish --dry-run --skip-validation 2>&1); ` +
  'if printf "%s\\n" "$listing" | grep -Eq "─ test_helper\\.dart( \\(|$)"; then echo "archive ships test_helper.dart" >&2; exit 1; fi); ' +
  'out=$(./scripts/ci/test.sh meta no-coverage); printf "%s\\n" "$out"; ' +
  'printf "%s\\n" "$out" | grep -qF "Meta tier inactive" || { echo "meta tier ran: a TestHelper ships" >&2; exit 1; }\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-testhelper-meta-contract-green',
      description: 'the TestHelper=NO verdict holds: no helper in the archive and the meta tier is a no-op',
      kind: 'baseline',
      async run(repo: any) {
        if ((await repo.glob(`${MEMBER}/{lib/test_helper.dart,test/meta/**}`)).length !== 0) {
          throw new Error('testhelper-meta-contract: the package ships a TestHelper or a meta suite');
        }
        await expectGreen(repo, NO_HELPER, 'testhelper-meta-contract');
      },
    },
    {
      name: 'mutation-testhelper-meta-contract-caught',
      description: 'the NO-verdict check fails once a TestHelper and its meta suite are added',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [HELPER, META_SUITE], async () => {
          await repo.write(HELPER, 'bool expectProbeSlug(String value) => value.isNotEmpty;\n');
          await repo.write(
            META_SUITE,
            "import 'package:diene_core_utils/test_helper.dart';\n" +
              "import 'package:test/test.dart';\n\n" +
              "void main() {\n  test('probe helper', () {\n    expect(expectProbeSlug('a'), isTrue);\n  });\n}\n",
          );
          await expectRedBecause(repo, NO_HELPER, 'testhelper-meta-contract', ['archive ships test_helper.dart']);
        });
      },
    },
  ],
};
