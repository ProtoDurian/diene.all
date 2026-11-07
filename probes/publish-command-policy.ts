import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const PUBLISH_SH = 'scripts/ci/publish.sh';
const MEMBER_PUBSPEC = 'packages/diene_interfaces/pubspec.yaml';
const STUB_DIR = '.probe-publish-stub';
// A recording `dart` stands in for the real one, so nothing is ever uploaded.
const STUB = '#!/usr/bin/env bash\nprintf \'%s|%s\\n\' "$(pwd -P)" "$*" >>"$PROBE_DART_CALLS"\n';

function publishCheck(version: string): string {
  return (
    "nix develop .#ci -c bash -c 'set -euo pipefail; root=$(pwd -P); " +
    `export PROBE_DART_CALLS="$root/${STUB_DIR}/calls"; chmod +x ${STUB_DIR}/dart; export PATH="$root/${STUB_DIR}:$PATH"; ` +
    `if ./scripts/ci/publish.sh v${version}-probe.mismatch >/dev/null 2>&1; then echo "publish ignored the version guard" >&2; exit 1; fi; ` +
    'if grep -q "pub publish" "$PROBE_DART_CALLS" 2>/dev/null; then echo "publish ran before the version guard" >&2; exit 1; fi; ' +
    `./scripts/ci/publish.sh v${version} >/dev/null; ` +
    'last=$(tail -n 1 "$PROBE_DART_CALLS"); ' +
    '[ "$last" = "$root/packages/diene_interfaces|pub publish --force" ] || { echo "publish ran as: $last" >&2; exit 1; }\''
  );
}

async function withStub(repo: any, extra: string[], body: (version: string) => Promise<void>): Promise<void> {
  await withCleanProbeState(repo, [STUB_DIR, ...extra], async () => {
    const version = (await repo.read(MEMBER_PUBSPEC)).match(/^version:\s*(\S+)\s*$/m)?.[1];
    if (!version) {
      throw new Error('publish-command-policy: member pubspec has no version');
    }
    await repo.write(`${STUB_DIR}/dart`, STUB);
    await body(version);
  });
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-publish-command-policy-green',
      description:
        'the tag path runs dart pub publish --force from the publishable member, only after the version guard passes',
      kind: 'baseline',
      async run(repo: any) {
        await withStub(repo, [], async version => {
          await expectGreen(repo, publishCheck(version), 'publish-command-policy');
        });
      },
    },
    {
      name: 'mutation-publish-command-policy-caught',
      description: 'the policy check fails once publish runs from the workspace root',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withStub(repo, [PUBLISH_SH], async version => {
          await repo.patch(PUBLISH_SH, {
            find: 'cd "${root_dir}/packages/diene_interfaces"',
            replace: 'cd "${root_dir}"',
          });
          await expectRedBecause(repo, publishCheck(version), 'publish-command-policy', ['publish ran as:']);
        });
      },
    },
  ],
};
