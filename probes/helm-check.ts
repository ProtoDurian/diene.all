import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-helm-check-green',
      description: 'The fresh render of the root chart passes chart-checks (schemas and the workspace VAP).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/helm-check.sh infra/root_chart', 'helm-check');
      },
    },
    {
      name: 'mutation-helm-check-caught',
      description: 'A chart that drops its LPSM labels must turn the helm-check mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/templates/configmap.yaml', { find: '  labels:', replace: '  annotations:' });
        await expectRed(repo, 'nix develop .#ci -c ./scripts/local/helm-check.sh infra/root_chart', 'helm-check');
      },
    },
  ],
};
