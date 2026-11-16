import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-helm-check-green',
      description: 'The generated Helm render-check hook passes the root chart.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#default -c pre-commit run a-helm-check --all-files', 'hook-helm-check');
      },
    },
    {
      name: 'mutation-hook-helm-check-caught',
      description: 'A workload that drops its LPSM labels must turn the hook-helm-check mechanism red.',
      kind: 'mutation',
      expectedImpact: ['helm-check'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/templates/deployment.yaml', {
          find: '        {{- range $key, $value := .Values.serviceTree }}',
          replace: '        {{- range $key, $value := dict }}',
        });
        await expectRed(repo, 'nix develop .#default -c pre-commit run a-helm-check --all-files', 'hook-helm-check');
      },
    },
  ],
};
