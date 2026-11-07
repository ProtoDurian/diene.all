import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const guard = (tag: string) => `nix develop .#ci -c ./scripts/validate/go-publish-guard.sh ${tag}`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-publish-semver-guard-green',
      description: 'The publication guard accepts an exact vX.Y.Z tag.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, guard('v1.2.3'), 'go-lib-publish-semver-guard');
      },
    },
    {
      name: 'mutation-go-lib-publish-semver-guard-caught',
      description: 'A malformed release tag is refused before the proxy is reached.',
      kind: 'mutation',
      async run(repo: any) {
        await expectRedWithDiagnostic(
          repo,
          guard('v1.2'),
          'go-lib-publish-semver-guard',
          /release tag 'v1\.2' must match vX\.Y\.Z/,
        );
      },
    },
  ],
};
