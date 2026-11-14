// A root-chart workload template for probes. The prefix and the reload mode come from chart values, never spelled out here.
export interface WorkloadOptions {
  podLabelOverride?: string; // replaces the pod reload label line
  helperChecks?: boolean; // false: leave out the workload-annotations helper, so only the admission policy can object
  spec?: object;
}

export const VALUES = 'infra/root_chart/values.yaml';

export function workload(opts: WorkloadOptions = {}): string {
  const spec = opts.spec ?? { containers: [{ name: 'c', image: 'nginx:1.27' }] };
  const lpsm = (indent: string) =>
    `{{- range $key, $value := .Values.serviceTree }}\n${indent}{{ $.Values.labelPrefix }}/{{ $key }}: {{ $value | quote }}\n${indent}{{- end }}`;
  const args = '(dict "root" $ "podSpec" $spec)';
  return [
    `{{- $spec := fromJson \`${JSON.stringify(spec)}\` -}}`,
    'apiVersion: apps/v1',
    'kind: Deployment',
    'metadata:',
    '  name: probe',
    '  labels:',
    `    ${lpsm('    ')}`,
    ...(opts.helperChecks === false
      ? []
      : [
          `  {{- with (include "root.reload.annotations" ${args} | trim) }}`,
          '  annotations:',
          '    {{- . | nindent 4 }}',
          '  {{- end }}',
        ]),
    'spec:',
    '  selector: {matchLabels: {app: probe}}',
    '  template:',
    '    metadata:',
    '      labels:',
    '        app: probe',
    `        ${lpsm('        ')}`,
    opts.podLabelOverride ?? `        {{- include "root.reload.label" ${args} | nindent 8 }}`,
    `      {{- with (include "root.reload.podAnnotations" ${args} | trim) }}`,
    '      annotations:',
    '        {{- . | nindent 8 }}',
    '      {{- end }}',
    '    spec:',
    '      {{- toYaml $spec | nindent 6 }}',
    '',
  ].join('\n');
}

export interface ValuesOptions {
  reload: string | null; // null leaves the key out, so the chart helper's default applies
  startOnly?: object[]; // restartOnlyConfigs entries
}

// Sets the two reload values of the root chart. Idempotent, so probes that share a sandbox never see each other's state.
// The shipped values file has no active `reload:` line (the helper holds the default), so a value is appended.
export async function setValues(repo: any, opts: ValuesOptions): Promise<void> {
  const reload =
    `sed -i '/^reload:/d' ${VALUES}` +
    (opts.reload === null ? '' : ` && printf 'reload: %s\\n' '${opts.reload}' >> ${VALUES}`);
  const startOnly = `sed -i 's/^restartOnlyConfigs:.*/restartOnlyConfigs: ${JSON.stringify(opts.startOnly ?? []).replaceAll('/', '\\/')}/'`;
  const result = await repo.exec(`${reload} && ${startOnly} ${VALUES}`);
  if (result.exitCode !== 0) throw new Error(`could not set the root chart values: ${result.stderr || result.stdout}`);
}
