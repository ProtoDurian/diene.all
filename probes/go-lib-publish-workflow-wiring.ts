import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c dlint ci-wiring';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-publish-workflow-wiring-green',
      description:
        'The tag-triggered CD job resolves through its reusable workflow to the publish guard and proxy check.',
      kind: 'baseline',
      async run(repo: any) {
        if (!(await repo.read('.github/workflows/cd.yaml')).includes('./.github/workflows/⚡reusable-publish.yaml')) {
          throw new Error('cd.yaml does not call ⚡reusable-publish.yaml');
        }
        const publish = await repo.read('scripts/ci/publish.sh');
        for (const step of ['./scripts/validate/go-publish-guard.sh', './scripts/validate/go-proxy-roundtrip.sh']) {
          if (!publish.includes(step)) {
            throw new Error(`scripts/ci/publish.sh does not reach ${step}`);
          }
        }
        await expectGreen(repo, gate, 'go-lib-publish-workflow-wiring');
      },
    },
    {
      name: 'mutation-go-lib-publish-workflow-wiring-caught',
      description: 'A publish workflow that calls a missing CI script turns wiring red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('.github/workflows/⚡reusable-publish.yaml', {
          find: './scripts/ci/publish.sh',
          replace: './scripts/ci/probe-missing-publish.sh',
        });
        await expectRedWithDiagnostic(repo, gate, 'go-lib-publish-workflow-wiring', /probe-missing-publish\.sh/);
      },
    },
  ],
};
