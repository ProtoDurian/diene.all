import { capturedEnvCommand, expectGreen, expectRed, expectRedBecause } from './lib/helpers.ts';

const CHECK = 'nix develop .#ci -c ./scripts/local/helm-check.sh infra/root_chart';
const PIN = '    commit: 560e7fc4ee8aae51cae8a00aa68aa4e4fe6af3e1\n';

// Runs the check and requires one exact exit code plus a refusal text (chart-checks: 3 = config refused, 4 = install failed).
async function expectExit(repo: any, code: number, reasons: readonly string[]): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(CHECK, 'helm-check'), { timeoutMs: 240000 });
  const output = `${result.stdout}\n${result.stderr}`;
  if (result.exitCode !== code) {
    throw new Error(`helm-check exited ${result.exitCode}, expected ${code}\n${output}`);
  }
  const missing = reasons.filter(reason => !output.includes(reason));
  if (missing.length > 0) throw new Error(`helm-check exit ${code} without (${missing.join(', ')})\n${output}`);
}
const LPSM = ['landscape', 'platform', 'service', 'module'].map(k => `{{ $.Values.labelPrefix }}/${k}: x`).join(', ');

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
      description:
        'A workload whose pod template lacks the LPSM labels must turn the helm-check mechanism red through the cluster-policies chart fetched from the stand-in.',
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
            `  labels: { ${LPSM} }`,
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
        await expectRedBecause(repo, CHECK, 'helm-check', ['require-lpsm-labels']);
      },
    },
    {
      name: 'mutation-helm-check-schema-caught',
      description: 'A schema-invalid object (unknown field) must turn the helm-check mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/templates/configmap.yaml', {
          find: 'data:',
          replace: 'bogusField: true\ndata:',
        });
        await expectRed(repo, CHECK, 'helm-check');
      },
    },
    {
      name: 'mutation-helm-check-prefix-caught',
      description: 'A label under a different prefix must turn the helm-check mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/templates/configmap.yaml', {
          find: '{{ $.Values.labelPrefix }}/{{ $key }}',
          replace: 'other.example/{{ $key }}',
        });
        await expectRed(repo, CHECK, 'helm-check');
      },
    },
    {
      name: 'mutation-helm-check-upstream-scope',
      description:
        'An upstream subchart may ship unlabelled non-workload objects and Helm test-hook Pods (green), but an unlabelled upstream Pod must turn the helm-check mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/Chart.yaml', {
          find: "appVersion: '0.1.0'",
          replace: "appVersion: '0.1.0'\ndependencies:\n  - name: upstream\n    version: 0.1.0",
        });
        await repo.write(
          'infra/root_chart/charts/upstream/Chart.yaml',
          'apiVersion: v2\nname: upstream\nversion: 0.1.0\n',
        );
        await repo.write(
          'infra/root_chart/charts/upstream/templates/role.yaml',
          'apiVersion: rbac.authorization.k8s.io/v1\nkind: ClusterRole\nmetadata:\n  name: upstream\nrules: []\n',
        );
        await repo.write(
          'infra/root_chart/charts/upstream/templates/test-pod.yaml',
          'apiVersion: v1\nkind: Pod\nmetadata:\n  name: upstream-test\n  annotations:\n    helm.sh/hook: test\nspec:\n  containers: [{name: c, image: "nginx:1.27"}]\n',
        );
        await expectGreen(repo, CHECK, 'helm-check');
        await repo.write(
          'infra/root_chart/charts/upstream/templates/pod.yaml',
          'apiVersion: v1\nkind: Pod\nmetadata:\n  name: upstream\nspec:\n  containers: [{name: c, image: "nginx:1.27"}]\n',
        );
        await expectRed(repo, CHECK, 'helm-check');
      },
    },
    {
      name: 'mutation-helm-check-second-policy-caught',
      description:
        'A second policies entry beside the pinned cluster-policies git entry keeps its own path and is still evaluated: its violated policy must turn the helm-check mechanism red, and removing the entry makes it green again.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.write(
          'infra/rendered/extra-policy/Chart.yaml',
          'apiVersion: v2\nname: extra-policy\nversion: 0.1.0\n',
        );
        await repo.write(
          'infra/rendered/extra-policy/templates/deny.yaml',
          [
            'apiVersion: admissionregistration.k8s.io/v1',
            'kind: ValidatingAdmissionPolicy',
            'metadata:',
            '  name: extra-deny-configmaps',
            'spec:',
            '  failurePolicy: Fail',
            '  matchConstraints:',
            '    resourceRules:',
            '      - apiGroups: [""]',
            '        apiVersions: ["v1"]',
            '        operations: ["CREATE", "UPDATE"]',
            '        resources: ["configmaps"]',
            '  validations:',
            '    - expression: "false"',
            '      message: The extra policy is violated.',
            '---',
            'apiVersion: admissionregistration.k8s.io/v1',
            'kind: ValidatingAdmissionPolicyBinding',
            'metadata:',
            '  name: extra-deny-configmaps',
            'spec:',
            '  policyName: extra-deny-configmaps',
            '  validationActions: [Deny]',
            '',
          ].join('\n'),
        );
        const entry = '    subpath: chart';
        const extra = '\n  - name: extra-policy\n    path: infra/rendered/extra-policy';
        await repo.patch('chart-checks.yaml', { find: entry, replace: entry + extra });
        await expectRedBecause(repo, CHECK, 'helm-check', ['extra-deny-configmaps']);
        await repo.patch('chart-checks.yaml', { find: entry + extra, replace: entry });
        await expectGreen(repo, CHECK, 'helm-check');
      },
    },
    {
      name: 'mutation-helm-check-wrong-commit-caught',
      description: 'A cluster-policies commit that cannot be fetched must fail the chart-checks install (exit 4).',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.patch('chart-checks.yaml', { find: PIN, replace: `    commit: ${'0'.repeat(40)}\n` });
        await expectExit(repo, 4, []);
      },
    },
    {
      name: 'mutation-helm-check-unpinned-caught',
      description: 'A cluster-policies entry without commit: must be refused by chart-checks (exit 3).',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.patch('chart-checks.yaml', { find: PIN, replace: '' });
        await expectExit(repo, 3, []);
      },
    },
    {
      name: 'mutation-helm-check-leaves-no-temp-config',
      description:
        'A failed helm-check run leaves no .chart-checks.stack.yaml in the repo and nothing in its temporary directory.',
      kind: 'mutation',
      expectedImpact: ['hook-helm-check'],
      async run(repo: any) {
        await repo.patch('infra/root_chart/templates/configmap.yaml', { find: '  labels:', replace: '  annotations:' });
        const run = capturedEnvCommand(
          'nix develop .#ci -c env TMPDIR="$tmp" ./scripts/local/helm-check.sh infra/root_chart',
          'helm-check',
        );
        const result = await repo.exec(
          [
            'tmp="$(mktemp -d)"',
            `${run}`,
            'rc=$?',
            '[ "$rc" -ne 0 ] || { echo "helm-check stayed green after sabotage"; exit 90; }',
            '[ -z "$(ls -A "$tmp")" ] || { echo "temporary directory not cleaned:"; ls -A "$tmp"; exit 91; }',
            'left="$(find . -name .chart-checks.stack.yaml -not -path "./.git/*" 2>/dev/null)"',
            '[ -z "$left" ] || { echo "leftover: $left"; exit 92; }',
          ].join('\n'),
          { timeoutMs: 240000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(`helm-check left state behind: ${result.stdout || result.stderr}`);
        }
      },
    },
  ],
};
