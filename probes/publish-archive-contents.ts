import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const PUBIGNORE = 'packages/diene_e2e/.pubignore';
const SHIPPED = [
  'diene_e2e.dart',
  'test_helper.dart',
  'diene_e2e.md',
  'LICENSE',
  'CHANGELOG.md',
  'README.md',
  'diene_e2e_example.dart',
  'diene-e2e-usage',
  'SKILL.md',
];
const EXCLUDED = ['test', 'tool', 'deadcode_entrypoints.dart', 'c0_conformance_test.dart', 'manifest.json'];

// The dry-run listing is a tree; match whole leaf names, with or without a size suffix.
const ARCHIVE_CHECK =
  "nix develop .#ci -c bash -c 'set -euo pipefail; cd packages/diene_e2e; " +
  'listing=$(dart pub publish --dry-run --skip-validation 2>&1); ' +
  `for f in ${SHIPPED.join(' ')}; do printf "%s\\n" "$listing" | grep -Eq "─ $f( \\(|\\$)" || { echo "archive is missing $f" >&2; exit 1; }; done; ` +
  `for f in ${EXCLUDED.join(' ')}; do if printf "%s\\n" "$listing" | grep -Eq "─ $f( \\(|\\$)"; then echo "archive ships $f" >&2; exit 1; fi; done'`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    post: ['nix develop .#ci -c flutter pub get --offline', 'rm -f .git/hooks/pre-commit .git/hooks/commit-msg'],
  },
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
            'archive is missing diene-e2e-usage',
          ]);
        });
      },
    },
  ],
};
