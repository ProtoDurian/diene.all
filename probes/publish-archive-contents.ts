import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const PUBIGNORE = 'packages/diene_core_utils/.pubignore';
const SHIPPED = [
  'diene_core_utils.dart',
  'c0_temporal.dart',
  'diene_core_utils.md',
  'LICENSE',
  'CHANGELOG.md',
  'README.md',
  'diene_core_utils_example.dart',
  'diene-core-utils-usage',
  'SKILL.md',
  'patterns.md',
];
const EXCLUDED = [
  'test',
  'tool',
  'test_helper.dart',
  'deadcode_entrypoints.dart',
  'gen_iana_zones.dart',
  'manifest.json',
];

// The dry-run listing is a tree; match whole leaf names, with or without a size suffix.
const ARCHIVE_CHECK =
  "nix develop .#ci -c bash -c 'set -euo pipefail; cd packages/diene_core_utils; " +
  'listing=$(dart pub publish --dry-run --skip-validation 2>&1); ' +
  `for f in ${SHIPPED.join(' ')}; do printf "%s\\n" "$listing" | grep -Eq "─ $f( \\(|\\$)" || { echo "archive is missing $f" >&2; exit 1; }; done; ` +
  `for f in ${EXCLUDED.join(' ')}; do if printf "%s\\n" "$listing" | grep -Eq "─ $f( \\(|\\$)"; then echo "archive ships $f" >&2; exit 1; fi; done'`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'] },
  probes: [
    {
      name: 'baseline-publish-archive-contents-green',
      description:
        'the dry-run archive ships barrel, docs, license, changelog, example and usage skill, and no dev or test files',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, ARCHIVE_CHECK, 'publish-archive-contents');
      },
    },
    {
      name: 'mutation-publish-archive-contents-caught',
      description: 'the archive check fails once .pubignore excludes the shipped skill',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [PUBIGNORE], async () => {
          await repo.write(PUBIGNORE, `${await repo.read(PUBIGNORE)}/skills/\n`);
          await expectRedBecause(repo, ARCHIVE_CHECK, 'publish-archive-contents', [
            'archive is missing diene-core-utils-usage',
          ]);
        });
      },
    },
  ],
};
