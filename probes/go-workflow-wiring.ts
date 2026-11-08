import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c dlint ci-wiring';
const lanes = ['⚡reusable-build.yaml', '⚡reusable-dead-code.yaml', '⚡reusable-test.yaml', '⚡reusable-vuln.yaml'];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-workflow-wiring-green',
      description: 'Every Go CI job resolves through its reusable workflow to an existing CI script.',
      kind: 'baseline',
      async run(repo: any) {
        for (const lane of lanes) {
          if (!(await repo.read(`.github/workflows/${lane}`)).includes('./scripts/ci/')) {
            throw new Error(`${lane} calls no scripts/ci entrypoint`);
          }
        }
        await expectGreen(repo, gate, 'go-workflow-wiring');
      },
    },
    {
      name: 'mutation-go-workflow-wiring-caught',
      description: 'A Go reusable workflow that calls a missing CI script must turn wiring red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('.github/workflows/⚡reusable-test.yaml', {
          find: './scripts/ci/test.sh',
          replace: './scripts/ci/probe-missing.sh',
        });
        await expectRedWithDiagnostic(repo, gate, 'go-workflow-wiring', /probe-missing\.sh/);
      },
    },
  ],
};
