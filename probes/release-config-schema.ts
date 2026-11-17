import { expectGreen, expectRed } from './lib/helpers.ts';

const CHECK =
  `message_path="$(mktemp)" && trap 'rm -f "$message_path"' EXIT && printf 'feat: valid commit message\\n' >"$message_path" && ` +
  'nix develop .#ci -c releaser lint-commit -c release.yaml "$message_path"';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-config-schema-green',
      description: 'release.yaml parses and is schema-valid.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, CHECK, 'release-config-schema');
      },
    },
    {
      name: 'mutation-release-config-malformed-caught',
      description: 'A malformed release.yaml must turn the release-config-schema mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write('release.yaml', 'schemaVersion: 2\ntypes: [\n');
        await expectRed(repo, CHECK, 'release-config-schema');
      },
    },
    {
      name: 'mutation-release-config-schema-caught',
      description: 'A schema-invalid release.yaml must turn the release-config-schema mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('release.yaml', { find: 'schemaVersion: 2', replace: 'schemaVersion: 999' });
        await expectRed(repo, CHECK, 'release-config-schema');
      },
    },
  ],
};
