import { restoreProbeState } from './lib/helpers.ts';
import { expectGreen, expectRedWithDiagnostic, plantGoFile } from './lib/go.ts';

// Per-process cache: concurrent probe arms must not share golangci results.
const gate =
  'GOLANGCI_LINT_CACHE="$PWD/.git/cyanprint-golangci-cache-$$" nix develop .#ci -c pre-commit run a-golangci-lint --all-files';
const whiteBox = /package should be `\w+_test` instead of `\w+` \(testpackage\)/;

const plants = [
  {
    name: 'mutation-go-black-box-hook-caught',
    description: 'A white-box Go test package must turn the golangci-lint hook red.',
    glob: 'lib/**/*.go',
    filename: 'probe_white_box_test.go',
    declaration: 'import "testing"\n\nfunc TestProbeWhiteBox(t *testing.T) { t.Helper() }',
  },
  {
    name: 'mutation-go-export-test-caught',
    description: 'An export_test.go backdoor must turn the golangci-lint hook red.',
    glob: 'lib/**/*.go',
    filename: 'export_test.go',
    declaration: 'var ProbeExported = 1',
  },
  {
    name: 'mutation-go-black-box-main-caught',
    description: 'A white-box test in the composition root must turn the golangci-lint hook red.',
    glob: 'cmd/**/*.go',
    filename: 'probe_white_box_test.go',
    declaration: 'import "testing"\n\nfunc TestProbeWhiteBox(t *testing.T) { t.Helper() }',
  },
];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-black-box-hook-green',
      description: 'The golangci-lint hook accepts only external Go test packages.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'hook-go-black-box');
      },
    },
    ...plants.map(plant => ({
      name: plant.name,
      description: plant.description,
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantGoFile(repo, plant.glob, plant.filename, plant.declaration);
        try {
          await expectRedWithDiagnostic(repo, gate, 'hook-go-black-box', whiteBox);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    })),
  ],
};
