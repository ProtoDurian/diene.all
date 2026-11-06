import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const ANALYZE = 'nix develop .#ci -c ./scripts/ci/analyze.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-dart-analyze-green',
      description: 'dart analyze passes the workspace with infos and warnings fatal',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, ANALYZE, 'dart-analyze');
      },
    },
    {
      name: 'mutation-dart-analyze-caught',
      description: 'dart analyze fails once a library source calls print, which the strict lints forbid',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = (await repo.glob('packages/*/lib/src/**/*.dart')).sort()[0];
        if (!target) {
          throw new Error('dart-analyze: no library source file to sabotage');
        }
        await withCleanProbeState(repo, [target], async () => {
          await repo.write(
            target,
            `${await repo.read(target)}\nvoid probeAnalyzeViolation() {\n  print('probe');\n}\n`,
          );
          await expectRedBecause(repo, ANALYZE, 'dart-analyze', ['avoid_print']);
        });
      },
    },
  ],
};
