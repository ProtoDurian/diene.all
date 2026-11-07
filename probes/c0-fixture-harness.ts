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
      description: 'the C0 harness fails once one pinned fixture digest is corrupted',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = (await repo.glob('packages/*/test/fixtures/c0/manifest.json')).sort()[0];
        if (!target) {
          throw new Error('c0-fixture-harness: no fixture manifest to sabotage');
        }
        await withCleanProbeState(repo, [target], async () => {
          const manifest = JSON.parse(await repo.read(target));
          const entries = manifest.fixtures ?? {};
          const first = Object.keys(entries).sort()[0];
          if (!first) {
            throw new Error('c0-fixture-harness: fixture manifest has no entries');
          }
          const digest = String(entries[first]);
          entries[first] = (digest[0] === '0' ? '1' : '0') + digest.slice(1);
          await repo.write(target, `${JSON.stringify(manifest, null, 2)}\n`);
          await expectRedBecause(repo, HARNESS, 'c0-fixture-harness', ['digest drifted from the manifest']);
        });
      },
    },
  ],
};
