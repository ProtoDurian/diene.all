import { restoreProbeState } from './lib/helpers.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const ciVulnGate = './scripts/ci/vuln.sh';
const fixtures = '.probe-govulncheck';
const scannerDouble = [
  '#!/usr/bin/env bash',
  'set -euo pipefail',
  'target="${*: -1}"',
  '[ ! -f "${target%/...}/govulncheck.json" ] && exit 0',
  'echo "$(jq -r \'.vulnerabilities[0].id\' "${target%/...}/govulncheck.json"): pinned vulnerable fixture detected" >&2',
  'exit 1',
  '',
].join('\n');
const vulnerable = '{"vulnerabilities":[{"id":"GO-2021-0113","module":"golang.org/x/text","version":"v0.3.0"}]}\n';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-govulncheck-green',
      description: 'The real blocking govulncheck CI entrypoint accepts the healthy module.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, `nix develop .#ci -c ${ciVulnGate}`, 'govulncheck', 600000);
      },
    },
    {
      name: 'mutation-govulncheck-caught',
      description: 'Routing a vulnerable fixture through a scanner double must redden the CI gate.',
      kind: 'mutation',
      async run(repo: any) {
        try {
          const created = await repo.exec(`mkdir -p ${fixtures}/vulnerable`);
          if (created.exitCode !== 0) {
            throw new Error(`could not create govulncheck fixtures: ${created.stderr}`);
          }
          await repo.write(`${fixtures}/govulncheck-double.sh`, scannerDouble);
          await repo.write(`${fixtures}/vulnerable/govulncheck.json`, vulnerable);
          await repo.exec(`chmod +x ${fixtures}/govulncheck-double.sh`);
          await expectRedWithDiagnostic(
            repo,
            `nix develop .#ci -c env GOVULNCHECK_BIN=./${fixtures}/govulncheck-double.sh GOVULNCHECK_TARGET=./${fixtures}/vulnerable ${ciVulnGate}`,
            'govulncheck',
            /GO-2021-0113: pinned vulnerable fixture detected/,
            600000,
          );
        } finally {
          await restoreProbeState(repo, [fixtures]);
        }
      },
    },
  ],
};
