import { expectGreen, expectRed } from './lib/helpers.ts';

const CHECK = 'nix develop .#ci -c ./scripts/local/helm-check.sh infra/root_chart';
const LPSM = ['landscape', 'platform', 'service', 'module'].map(k => `durian.cloud/${k}: x`).join(', ');

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-helm-check-green',
      description: 'The fresh render of the root chart passes chart-checks (schemas and the workspace VAP).',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, CHECK, 'helm-check');
      },
    },
    {
      name: 'mutation-helm-check-caught',
      description: 'A first-party object that drops its LPSM labels must turn the helm-check mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/templates/configmap.yaml', { find: '  labels:', replace: '  annotations:' });
        await expectRed(repo, CHECK, 'helm-check');
      },
    },
    {
      name: 'mutation-helm-check-pod-template-caught',
      description: 'A workload whose pod template lacks the LPSM labels must turn the helm-check mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.write(
          'infra/root_chart/templates/probe-deploy.yaml',
          [
            'apiVersion: apps/v1',
            'kind: Deployment',
            'metadata:',
            '  name: probe',
            `  labels: {${LPSM}}`,
            'spec:',
            '  selector: {matchLabels: {app: probe}}',
            '  template:',
            '    metadata:',
            '      labels: {app: probe}',
            '    spec:',
            '      containers: [{name: c, image: "nginx:1.27"}]',
            '',
          ].join('\n'),
        );
        await expectRed(repo, CHECK, 'helm-check');
      },
    },
    {
      name: 'mutation-helm-check-upstream-scope',
      description:
        'An upstream subchart may ship unlabelled non-workload objects (green), but an unlabelled upstream Pod must turn the helm-check mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.write(
          'infra/root_chart/charts/upstream/Chart.yaml',
          'apiVersion: v2\nname: upstream\nversion: 0.1.0\n',
        );
        await repo.write(
          'infra/root_chart/charts/upstream/templates/role.yaml',
          'apiVersion: rbac.authorization.k8s.io/v1\nkind: ClusterRole\nmetadata:\n  name: upstream\nrules: []\n',
        );
        await expectGreen(repo, CHECK, 'helm-check');
        await repo.write(
          'infra/root_chart/charts/upstream/templates/pod.yaml',
          'apiVersion: v1\nkind: Pod\nmetadata:\n  name: upstream\nspec:\n  containers: [{name: c, image: "nginx:1.27"}]\n',
        );
        await expectRed(repo, CHECK, 'helm-check');
      },
    },
  ],
};
