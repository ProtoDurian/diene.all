import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const LEDGER = 'nix develop .#ci -c ./scripts/ci/test.sh meta coverage';
const REPORT = 'reports/meta/lcov.info';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
  probes: [
    {
      name: 'baseline-testhelper-meta-coverage-ledger-green',
      description: 'the meta ledger is 100% and scoped to the TestHelper only',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, LEDGER, 'testhelper-meta-coverage-ledger');
        const sources = (await repo.read(REPORT)).split('\n').filter((line: string) => line.startsWith('SF:'));
        if (sources.length === 0 || !sources.every((line: string) => /(:|\/)lib\/test_helper\.dart$/.test(line))) {
          throw new Error(
            `testhelper-meta-coverage-ledger: ledger is not scoped to the TestHelper: ${sources.join(', ')}`,
          );
        }
      },
    },
    {
      name: 'mutation-testhelper-meta-coverage-ledger-caught',
      description: 'the meta ledger fails once an uncovered helper member is added',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = (await repo.glob('packages/*/lib/test_helper.dart')).sort()[0];
        if (!target) {
          throw new Error('testhelper-meta-coverage-ledger: no lib/test_helper.dart to sabotage');
        }
        await withCleanProbeState(repo, [target, 'reports/meta'], async () => {
          await repo.write(target, `${await repo.read(target)}\nint probeUncoveredHelper() {\n  return 1;\n}\n`);
          await expectRedBecause(repo, LEDGER, 'testhelper-meta-coverage-ledger', ['meta coverage is not 100%']);
        });
      },
    },
  ],
};
