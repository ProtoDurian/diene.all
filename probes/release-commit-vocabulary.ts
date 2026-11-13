import { expectGreen, expectRed } from './lib/helpers.ts';

const TYPES = 'amend,build,chore,ci,config,dep,docs,feat,fix,perf,refactor,style,test';
// The whole test runs inside the shell: entering it may print to stdout, which must not reach the comparison.
const VOCABULARY = `nix develop .#ci -c bash -c 'test "$(yq -r ".types[].type" release.yaml | paste -sd, -)" = "${TYPES}"'`;
const lint = (type: string) =>
  `message_path="$(mktemp)" && trap 'rm -f "$message_path"' EXIT && printf '${type}: valid commit message\\n' >"$message_path" && ` +
  'nix develop .#ci -c releaser lint-commit -c release.yaml "$message_path"';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-commit-vocabulary-green',
      description: 'release.yaml allows exactly the unified commit types and lint-commit accepts each one.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, VOCABULARY, 'release-commit-vocabulary');
        for (const type of TYPES.split(',')) {
          await expectGreen(repo, lint(type), 'release-commit-vocabulary');
        }
      },
    },
    {
      name: 'mutation-release-commit-vocabulary-caught',
      description: 'A commit with a removed type (merge) must turn lint-commit red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await expectRed(repo, lint('merge'), 'release-commit-vocabulary');
      },
    },
    {
      name: 'mutation-release-commit-vocabulary-drift-caught',
      description: 'Dropping a type from release.yaml must turn the vocabulary check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('release.yaml', { find: '  - type: amend\n', replace: '  - type: removed-type\n' });
        await expectRed(repo, VOCABULARY, 'release-commit-vocabulary');
      },
    },
  ],
};
