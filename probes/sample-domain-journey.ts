import { expectGreen } from './lib/go.ts';

const journey =
  "./scripts/local/build.sh && go test -count=1 -run '^TestCompiledArtifactRedisJourney$' ./tests/sit/cli";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-sample-domain-journey-green',
      description: 'The replaceable domain and KV adapter complete the compiled SIT journey.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, `nix develop .#ci -c bash -c "${journey}"`, 'sample-domain-journey');
      },
    },
  ],
};
