import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const DEADCODE = 'nix develop .#ci -c ./scripts/ci/deadcode.sh';
const FIXTURE = 'packages/diene_dart_lib/lib/src/probe_dead_whole.dart';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline'] },
  probes: [
    {
      name: 'baseline-deadcode-whole-package-green',
      description: 'both no-exclusion dead-code views are clean',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, DEADCODE, 'deadcode-whole-package');
      },
    },
    {
      name: 'mutation-deadcode-whole-package-caught',
      description:
        'the whole-package view (package + tests) flags an unused production file before the production view runs',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [FIXTURE], async () => {
          await repo.write(FIXTURE, 'int _probeDeadWhole() => 1;\n\nint probeDeadWhole() => _probeDeadWhole();\n');
          await expectRedBecause(repo, DEADCODE, 'deadcode-whole-package', ['probe_dead_whole.dart'], {
            forbidden: ['Production dead-code pass'],
          });
        });
      },
    },
  ],
};
