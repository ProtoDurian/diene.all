import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const HARNESS = "nix develop .#ci -c bash -c 'cd packages/diene_interfaces && dart test test/conformance'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
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
      description: 'the C0 harness fails once the vendored upstream envelope vector is altered',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = (await repo.glob('packages/*/test/fixtures/c0/upstream/envelopes.json')).sort()[0];
        if (!target) {
          throw new Error('c0-fixture-harness: no upstream envelope vector to sabotage');
        }
        await withCleanProbeState(repo, [target], async () => {
          const vectors = JSON.parse(await repo.read(target));
          const first = vectors.valid?.[0];
          if (!first) {
            throw new Error('c0-fixture-harness: upstream envelope vector has no valid case');
          }
          first.status = first.status === 410 ? 409 : 410;
          await repo.write(target, `${JSON.stringify(vectors, null, 2)}\n`);
          await expectRedBecause(repo, HARNESS, 'c0-fixture-harness', ['digest drifted from the manifest']);
        });
      },
    },
  ],
};
