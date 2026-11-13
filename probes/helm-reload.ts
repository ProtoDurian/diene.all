import { expectGreen, expectRed } from './lib/helpers.ts';
import { NO_START_ONLY, RELOAD_LINE, VALUES, workload } from './lib/helm-workload.ts';

const CHECK = 'nix develop .#ci -c ./scripts/local/helm-check.sh infra/root_chart';
const TEMPLATE = 'infra/root_chart/templates/probe-deploy.yaml';
const container = { name: 'c', image: 'nginx:1.27' };
const envFrom = { containers: [{ ...container, envFrom: [{ configMapRef: { name: 'cfg' } }] }] };
const atomiEnv = { containers: [{ ...container, env: [{ name: 'ATOMI_DB__HOST', value: 'x' }] }] };
const startOnly = (via: string) => `restartOnlyConfigs: [{kind: configmap, name: cfg, via: ${via}}]`;

async function live(repo: any) {
  await repo.patch(VALUES, { find: RELOAD_LINE, replace: '\nreload: live\n' });
}
async function listStartOnly(repo: any, via = 'envFrom') {
  await repo.patch(VALUES, { find: NO_START_ONLY, replace: startOnly(via) });
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-helm-reload-green',
      description: 'A restart workload using the reload helpers passes the render check.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write(TEMPLATE, workload());
        await expectGreen(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'baseline-helm-reload-live-green',
      description: 'A live workload with no env, envFrom or subPath config passes the render check.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write(TEMPLATE, workload());
        await live(repo);
        await expectGreen(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'baseline-helm-reload-start-only-green',
      description: 'A live workload with an envFrom ConfigMap declared in restartOnlyConfigs passes the render check.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write(TEMPLATE, workload({ spec: envFrom }));
        await live(repo);
        await listStartOnly(repo);
        await expectGreen(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'baseline-helm-reload-policy-start-only-green',
      description:
        'The admission policy admits a live pod whose envFrom ConfigMap is in its restart-configs annotation.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write(TEMPLATE, workload({ spec: envFrom, helperChecks: false }));
        await live(repo);
        await listStartOnly(repo);
        await expectGreen(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'mutation-helm-reload-missing-caught',
      description: 'A pod template without the reload label must turn the helm-reload mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(TEMPLATE, workload({ podLabelOverride: '' }));
        await expectRed(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'mutation-helm-reload-value-caught',
      description: 'A reload label of "sometimes" must turn the helm-reload mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(
          TEMPLATE,
          workload({ podLabelOverride: '        {{ $.Values.labelPrefix }}/reload: sometimes' }),
        );
        await expectRed(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'mutation-helm-reload-required-caught',
      description: 'A chart with no reload value must fail the render.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(TEMPLATE, workload());
        await repo.patch(VALUES, { find: RELOAD_LINE, replace: '\n' });
        await expectRed(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'mutation-helm-reload-live-envfrom-caught',
      description: 'A live workload that takes config through envFrom must fail the render.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(TEMPLATE, workload({ spec: envFrom }));
        await live(repo);
        await expectRed(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'mutation-helm-reload-policy-live-envfrom-caught',
      description:
        'The admission policy must refuse a live pod with an unlisted envFrom ConfigMap even without the helper.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(TEMPLATE, workload({ spec: envFrom, helperChecks: false }));
        await live(repo);
        await expectRed(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'mutation-helm-reload-live-env-caught',
      description: 'A live workload that sets an ATOMI_* env var must fail the render.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(TEMPLATE, workload({ spec: atomiEnv }));
        await live(repo);
        await expectRed(repo, CHECK, 'helm-reload');
      },
    },
    {
      name: 'mutation-helm-reload-start-only-via-caught',
      description: 'A restartOnlyConfigs entry with a bad via (a whole-folder mount) must fail the render.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(TEMPLATE, workload());
        await live(repo);
        await listStartOnly(repo, 'folder');
        await expectRed(repo, CHECK, 'helm-reload');
      },
    },
  ],
};
