import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const META = 'nix develop .#ci -c ./scripts/ci/test.sh meta no-coverage';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-testhelper-meta-contract-green',
      description: 'the independently invoked meta suite passes against the shipped TestHelper',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, META, 'testhelper-meta-contract');
      },
    },
    {
      name: 'mutation-testhelper-meta-contract-caught',
      description: 'the meta suite fails once expectNone stops rejecting Some',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = (await repo.glob('packages/*/lib/test_helper.dart')).sort()[0];
        if (!target) {
          throw new Error('testhelper-meta-contract: no lib/test_helper.dart to sabotage');
        }
        await withCleanProbeState(repo, [target], async () => {
          await repo.patch(target, {
            find: 'if (actual case Some<T>(:final value)) {',
            replace: 'if (actual case Some<T>(:final value) when false) {',
          });
          await expectRedBecause(repo, META, 'testhelper-meta-contract', ['Some tests failed']);
        });
      },
    },
  ],
};
