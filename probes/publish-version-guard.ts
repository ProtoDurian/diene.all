import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const MEMBER_PUBSPEC = 'packages/diene_result/pubspec.yaml';

function manifestVersion(source: string): string {
  const version = source.match(/^version:\s*(\S+)\s*$/m)?.[1];
  if (!version) {
    throw new Error('publish-version-guard: member pubspec has no version');
  }
  return version;
}

// An unroutable hosted URL keeps a broken guard from ever reaching pub.dev.
function publishAt(tag: string): string {
  return `nix develop .#ci -c bash -c 'PUB_HOSTED_URL=http://127.0.0.1:9 ./scripts/ci/publish.sh ${tag}'`;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-version-guard-green',
      description: 'the guard accepts the tag that equals the member pubspec version and leaves the manifest untouched',
      kind: 'baseline',
      async run(repo: any) {
        const before = await repo.read(MEMBER_PUBSPEC);
        await expectGreen(
          repo,
          `nix develop .#ci -c ./scripts/validate/publish-version.sh v${manifestVersion(before)}`,
          'publish-version-guard',
        );
        if ((await repo.read(MEMBER_PUBSPEC)) !== before) {
          throw new Error('publish-version-guard: the guard mutated the member pubspec');
        }
      },
    },
    {
      name: 'mutation-publish-version-guard-caught',
      description: 'publish.sh exits 1 before publication once the manifest and tag disagree, without restamping',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [MEMBER_PUBSPEC], async () => {
          const original = await repo.read(MEMBER_PUBSPEC);
          const version = manifestVersion(original);
          const drifted = original.replace(/^version:.*$/m, `version: ${version}-probe.drift`);
          await repo.write(MEMBER_PUBSPEC, drifted);
          await expectRedBecause(repo, publishAt(`v${version}`), 'publish-version-guard', ['!= tag version'], {
            forbidden: ['Publishing diene_result'],
          });
          if ((await repo.read(MEMBER_PUBSPEC)) !== drifted) {
            throw new Error('publish-version-guard: publish restamped the member pubspec');
          }
        });
      },
    },
  ],
};
