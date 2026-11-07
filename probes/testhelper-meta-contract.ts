import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const META = 'nix develop .#ci -c ./scripts/ci/test.sh meta no-coverage';
const FIND = 'if (actual == expected) return;';

async function findHelperSource(repo: any): Promise<string | undefined> {
  for (const candidate of (await repo.glob('packages/*/lib/**/*.dart')).sort()) {
    if ((await repo.read(candidate)).includes(FIND)) {
      return candidate;
    }
  }
  return undefined;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
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
      description: 'the meta suite fails once the TestHelper equality assertion is inverted',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = await findHelperSource(repo);
        if (!target) {
          throw new Error(`testhelper-meta-contract: no TestHelper source contains ${FIND}`);
        }
        await withCleanProbeState(repo, [target], async () => {
          await repo.patch(target, { find: FIND, replace: 'if (actual != expected) return;' });
          await expectRedBecause(repo, META, 'testhelper-meta-contract', ['Some tests failed']);
        });
      },
    },
  ],
};
