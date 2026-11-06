import { expectGreen } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/ci/sit.sh';
const gateTimeoutMs = 600000;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-system-integration-tests-green',
      description:
        'The CI system-integration entrypoint builds the artifact and runs the sample Note/KV journey against Redis.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'system-integration-tests', gateTimeoutMs);
      },
    },
  ],
};
