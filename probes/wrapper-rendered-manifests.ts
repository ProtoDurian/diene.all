import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const command = 'nix develop .#ci -c pre-commit run a-wrapper-manifests --all-files';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-rendered-manifests-green',
    description:
      'chart-checks (kubectl-validate with the installed CRDs, then the installed vanadium VAP definitions) accepts every committed stack, upstream objects included, and the all-on stack.',
    async run(repo: any) {
      await expectGreen(repo, command, 'wrapper-rendered-manifests');
      await expectGreen(
        repo,
        'nix develop .#ci -c ./probes/checks/helm-wrapper.sh all-on-manifests',
        'wrapper-rendered-manifests',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-rendered-manifests-caught',
    description: 'The one wiring fault, an upstream image tagged latest, is denied by the vanadium rule.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('chart/values.yaml', {
        find: '            repository: ghcr.io/stefanprodan/podinfo\n            tag: 6.9.2\n',
        replace: '            repository: ghcr.io/stefanprodan/podinfo\n            tag: latest\n',
      });
      await expectRedBecause(repo, command, 'wrapper-rendered-manifests', ['vanadium-disallowlatest']);
    },
  },
});
