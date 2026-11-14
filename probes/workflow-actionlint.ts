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
    {
      name: 'mutation-workflow-cache-tag-without-setup-nix-caught',
      description: 'A cache-tag label on a job with no setup-nix step must turn the ci-cache-rules named check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const check = 'nix develop .#ci -c ./.github/named-checks/workspace/ci-cache-rules.sh';
        await expectGreen(repo, check, 'workflow-actionlint');
        await repo.patch('.github/workflows/⚡reusable-release-note.yaml', {
          find: 'runs-on: ubuntu-26.04',
          replace: 'runs-on: [ubuntu-26.04, nscloud-cache-tag-nix-store-cache-ubuntu-26.04-amd64]',
        });
        await expectRedBecause(repo, check, 'workflow-actionlint', ['no AtomiCloud/actions.setup-nix step']);
      },
    },
    {
      name: 'mutation-workflow-id-token-without-flakehub-login-caught',
      description:
        'A job with id-token: write and a setup-nix step without flakehub-login false must turn the ci-cache-rules named check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const check = 'nix develop .#ci -c ./.github/named-checks/workspace/ci-cache-rules.sh';
        await expectGreen(repo, check, 'workflow-actionlint');
        await repo.patch('.github/workflows/⚡reusable-named-checks.yaml', {
          find: '    timeout-minutes: 20\n',
          replace: '    timeout-minutes: 20\n    permissions:\n      id-token: write\n',
        });
        await expectRedBecause(repo, check, 'workflow-actionlint', ['flakehub-login']);
      },
    },
    {
      name: 'mutation-workflow-devshell-cache-without-keep-caught',
      description: 'A devshell-cache job without DURIAN_SHELL_KEEP must turn the ci-cache-rules named check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const check = 'nix develop .#ci -c ./.github/named-checks/workspace/ci-cache-rules.sh';
        await expectGreen(repo, check, 'workflow-actionlint');
        await repo.patch('.github/workflows/⚡reusable-named-checks.yaml', {
          find: "    env:\n      DURIAN_SHELL_KEEP: '64'\n",
          replace: '',
        });
        await expectRedBecause(repo, check, 'workflow-actionlint', ['DURIAN_SHELL_KEEP']);
      },
    },
    {
      name: 'mutation-workflow-top-level-id-token-without-flakehub-login-caught',
      description:
        'A workflow-level id-token: write inherited by a setup-nix job without flakehub-login false must turn the ci-cache-rules named check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const check = 'nix develop .#ci -c ./.github/named-checks/workspace/ci-cache-rules.sh';
        await expectGreen(repo, check, 'workflow-actionlint');
        await repo.patch('.github/workflows/⚡reusable-named-checks.yaml', {
          find: 'jobs:\n',
          replace: 'permissions:\n  id-token: write\n\njobs:\n',
        });
        await expectRedBecause(repo, check, 'workflow-actionlint', ['flakehub-login']);
      },
    },
  ],
};
