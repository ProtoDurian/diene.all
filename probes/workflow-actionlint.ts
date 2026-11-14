import { expectGreen, expectRed, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-workflow-actionlint-green',
      description: 'Actionlint accepts every workflow independently of job-to-script validation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c actionlint', 'workflow-actionlint');
      },
    },
    {
      name: 'mutation-workflow-actionlint-caught',
      description: 'A focused sabotage must turn the workflow-actionlint mechanism red.',
      kind: 'mutation',
      expectedImpact: ['fmt-actionlint'],
      async run(repo: any) {
        const path = '.github/workflows/⚡reusable-precommit.yaml';
        const original = await repo.read(path);
        try {
          await repo.patch(path, {
            find: '        run: durian-shell .#ci -c ./scripts/ci/pre-commit.sh',
            replace: '        runs: durian-shell .#ci -c ./scripts/ci/pre-commit.sh',
          });
          await expectRed(repo, 'nix develop .#ci -c actionlint', 'workflow-actionlint');
        } finally {
          await repo.write(path, original);
        }
      },
    },
    {
      name: 'mutation-workflow-runner-latest-caught',
      description: 'A runs-on label ending in -latest in a workflow must turn the runner-labels check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const check = 'nix develop .#ci -c ./scripts/local/pre-commit-run.sh a-runner-labels --all-files';
        await expectGreen(repo, check, 'workflow-actionlint');
        await repo.patch('.github/workflows/⚡reusable-release-note.yaml', {
          find: 'runs-on: ubuntu-26.04',
          replace: 'runs-on: ubuntu-latest',
        });
        await expectRedBecause(repo, check, 'workflow-actionlint', ['ends in -latest']);
      },
    },
  ],
};
