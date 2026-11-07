import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const FORMAT = 'nix develop .#ci -c dart format --output=none --set-exit-if-changed .';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dart-format-green',
      description: 'dart format reports package, tests, examples and tooling as already formatted',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, FORMAT, 'dart-format');
      },
    },
    {
      name: 'mutation-dart-format-caught',
      description: 'dart format fails once one library source drifts from canonical style',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = (await repo.glob('packages/*/lib/src/**/*.dart')).sort()[0];
        if (!target) {
          throw new Error('dart-format: no library source file to sabotage');
        }
        await withCleanProbeState(repo, [target], async () => {
          await repo.write(target, `${await repo.read(target)}\nfinal int probeUnformatted =  1;\n`);
          await expectRedBecause(repo, FORMAT, 'dart-format', [target]);
        });
      },
    },
  ],
};
