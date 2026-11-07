import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const HARNESS = "nix develop .#ci -c bash -c 'cd packages/diene_auth_engine && flutter test test/conformance'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
  probes: [
    {
      name: 'baseline-c0-fixture-harness-green',
      description: 'the C0 harness verifies the pinned fixture checksums and round-trips each fixture',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, HARNESS, 'c0-fixture-harness');
      },
    },
    {
      name: 'mutation-c0-fixture-harness-caught',
      description: 'the conformance harness fails once the vendored upstream app-handoff vector is altered',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = (await repo.glob('packages/*/test/fixtures/c0/upstream/app_handoff.json')).sort()[0];
        if (!target) {
          throw new Error('c0-fixture-harness: no upstream app-handoff vector to sabotage');
        }
        await withCleanProbeState(repo, [target], async () => {
          const vectors = JSON.parse(await repo.read(target));
          vectors.defaultMount = '/probe-handoff';
          await repo.write(target, `${JSON.stringify(vectors, null, 2)}\n`);
          await expectRedBecause(repo, HARNESS, 'c0-fixture-harness', ['digest drifted from the manifest']);
        });
      },
    },
  ],
};
