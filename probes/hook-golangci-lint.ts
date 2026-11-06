import { restoreProbeState } from './lib/helpers.ts';
import { expectGreen, expectRedWithDiagnostic, plantGoFile } from './lib/go.ts';

// Per-process cache: concurrent probe arms must not share golangci results.
const gate =
  'GOLANGCI_LINT_CACHE="$PWD/.git/cyanprint-golangci-cache-$$" nix develop .#ci -c pre-commit run a-golangci-lint --all-files';

const goSources = 'lib/**/*.go';
const fixture = 'probe_ineffectual_assignment.go';

// Exported so unused stays quiet and ineffassign owns the red.
const ineffectualAssignment = [
  'func ProbeIneffectualAssignment() string {',
  '\tvalue := "probe"',
  '\tvalue = "probe-sabotage"',
  '\treturn value',
  '}',
].join('\n');

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-golangci-hook-green',
      description: 'The generated golangci-lint hook passes the healthy Go source.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'hook-golangci-lint');
      },
    },
    {
      name: 'mutation-golangci-hook-caught',
      description: 'A native ineffassign violation must turn the owning hook red.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantGoFile(repo, goSources, fixture, ineffectualAssignment);
        try {
          await expectRedWithDiagnostic(
            repo,
            gate,
            'hook-golangci-lint',
            /probe_ineffectual_assignment\.go:\d+:\d+: ineffectual assignment to \w+ \(ineffassign\)/,
          );
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
