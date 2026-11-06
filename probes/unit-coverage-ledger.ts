import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const LEDGER = 'nix develop .#ci -c ./scripts/ci/test.sh unit coverage';
const REPORT = 'reports/unit/lcov.info';

async function findBarrel(repo: any): Promise<string> {
  for (const candidate of (await repo.glob('packages/*/lib/*.dart')).sort()) {
    if ((await repo.read(candidate)).includes("export 'src/")) {
      return candidate;
    }
  }
  throw new Error('unit-coverage-ledger: no library barrel exporting src/ found');
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-unit-coverage-ledger-green',
      description: 'the unit ledger is 100% and covers every shipped lib/ file except the TestHelper',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, LEDGER, 'unit-coverage-ledger');
        const sources = (await repo.read(REPORT)).split('\n').filter((line: string) => line.startsWith('SF:'));
        if (
          sources.length === 0 ||
          !sources.every((line: string) => /\/lib\/.*\.dart$/.test(line) && !line.endsWith('/lib/test_helper.dart'))
        ) {
          throw new Error(
            `unit-coverage-ledger: ledger is not scoped to shipped lib/ minus the TestHelper: ${sources.join(', ')}`,
          );
        }
      },
    },
    {
      name: 'mutation-unit-coverage-ledger-caught',
      description: 'the unit ledger fails once an uncovered member outside lib/src is exported from the barrel',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const barrel = await findBarrel(repo);
        const fixture = barrel.replace(/\/lib\/[^/]+$/, '/lib/probe_uncovered.dart');
        await withCleanProbeState(repo, [barrel, fixture, 'reports/unit'], async () => {
          await repo.write(fixture, 'int probeUncovered() {\n  return 1;\n}\n');
          await repo.write(barrel, `${await repo.read(barrel)}\nexport 'probe_uncovered.dart';\n`);
          await expectRedBecause(repo, LEDGER, 'unit-coverage-ledger', ['unit coverage is not 100%']);
        });
      },
    },
  ],
};
