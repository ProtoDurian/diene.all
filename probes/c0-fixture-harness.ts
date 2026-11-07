import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const HARNESS = "nix develop .#ci -c bash -c 'cd packages/diene_config && dart test test/conformance'";
const VECTOR = 'packages/diene_config/test/fixtures/c0/upstream/layering_and_indexed_list.json';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-c0-fixture-harness-green',
      description: 'the C0 harness verifies the pinned local and upstream fixture digests and exercises each vector',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, HARNESS, 'c0-fixture-harness');
      },
    },
    {
      name: 'mutation-c0-fixture-harness-caught',
      description: 'the C0 harness fails once the vendored upstream layering vector expects a different value',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [VECTOR], async () => {
          await repo.patch(VECTOR, { find: '"retries": 2', replace: '"retries": 3' });
          await expectRedBecause(repo, HARNESS, 'c0-fixture-harness', [
            'upstream vector file "layering_and_indexed_list.json" digest drifted from the manifest',
          ]);
        });
      },
    },
  ],
};
