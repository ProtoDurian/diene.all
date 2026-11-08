import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const PUBIGNORE = 'packages/diene_auth_engine/.pubignore';
const CONSUMER = 'nix develop .#ci -c ./scripts/ci/test.sh consumer';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
  probes: [
    {
      name: 'baseline-consumer-test-green',
      description:
        'a fresh project installs the preloaded local pub archive, imports every public library, runs, compiles and type-checks',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, CONSUMER, 'consumer-test');
      },
    },
    {
      name: 'mutation-consumer-test-caught',
      description: 'the consumer fails to compile once .pubignore drops a source file the barrel exports',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [PUBIGNORE], async () => {
          await repo.write(PUBIGNORE, `${await repo.read(PUBIGNORE)}/lib/src/returnto/return_to.dart\n`);
          await expectRedBecause(repo, CONSUMER, 'consumer-test', [
            "Error when reading '../pub-cache/hosted/",
            "lib/src/returnto/return_to.dart': No such file or directory",
          ]);
        });
      },
    },
  ],
};
