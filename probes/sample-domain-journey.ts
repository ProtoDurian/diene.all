import { expectGreen } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-sample-domain-journey-green',
      description: 'The replaceable domain and KV adapter complete the compiled SIT journey.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/ci/sit.sh', 'sample-domain-journey');
      },
    },
  ],
};
