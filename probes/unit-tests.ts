import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';
import { flipAssertion } from './lib/mutations.ts';

const UNIT = 'nix develop .#ci -c ./scripts/ci/test.sh unit no-coverage';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-unit-tests-green',
      description: 'the unit suite exercises the sample through its public barrel and passes',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, UNIT, 'unit-tests');
      },
    },
    {
      name: 'mutation-unit-tests-caught',
      description: 'the unit suite fails once one structurally selected boolean assertion is flipped',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const tests = await repo.glob('packages/*/test/unit/**/*_test.dart');
        if (tests.length === 0) {
          throw new Error('unit-tests: no unit test file to sabotage');
        }
        await withCleanProbeState(repo, tests, async () => {
          await flipAssertion(repo, {
            globs: ['packages/*/test/unit/**/*_test.dart'],
            replacements: [
              { find: /\bexpect\(([^\n]+),\s*isFalse\)/, replace: 'expect($1, isTrue)' },
              { find: /\bexpect\(([^\n]+),\s*isTrue\)/, replace: 'expect($1, isFalse)' },
            ],
          });
          await expectRedBecause(repo, UNIT, 'unit-tests', ['Some tests failed']);
        });
      },
    },
  ],
};
