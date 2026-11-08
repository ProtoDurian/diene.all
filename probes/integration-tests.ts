import { restoreProbeState } from './lib/helpers.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c task test:int';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-integration-tests-green',
      description: 'The integration tier is green, including the empty tier of a library with no adapters.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'integration-tests');
      },
    },
    {
      name: 'mutation-integration-tests-caught',
      description: 'A failing test under tests/int must turn the integration tier red, even with no adapters.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = 'tests/int/probefail/probe_fail_test.go';
        await repo.write(
          planted,
          'package probefail_test\n\nimport "testing"\n\nfunc TestProbeIntegrationFails(t *testing.T) {\n\tt.Fatal("probe: integration tier ran a failing test")\n}\n',
        );
        try {
          await expectRedWithDiagnostic(repo, gate, 'integration-tests', /probe: integration tier ran a failing test/);
        } finally {
          await restoreProbeState(repo, ['tests/int/probefail']);
        }
      },
    },
  ],
};
