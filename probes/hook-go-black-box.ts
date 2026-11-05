import { restoreProbeState } from './lib/helpers.ts';
import { expectGreen, expectRedWithDiagnostic, plantGoFile } from './lib/go.ts';

const gate = 'nix develop .#ci -c pre-commit run a-golangci-lint --all-files';
const whiteBox = /package should be `\w+_test` instead of `\w+` \(testpackage\)/;

const plants = [
  {
    name: 'mutation-go-black-box-hook-caught',
    description: 'A white-box Go test package must turn the golangci-lint hook red.',
    filename: 'probe_white_box_test.go',
    declaration: 'import "testing"\n\nfunc TestProbeWhiteBox(t *testing.T) { t.Helper() }',
  },
  {
    name: 'mutation-go-export-test-caught',
    description: 'An export_test.go backdoor must turn the golangci-lint hook red.',
    filename: 'export_test.go',
    declaration: 'var ProbeExported = 1',
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
        const planted = await plantGoFile(repo, 'lib/**/*.go', plant.filename, plant.declaration);
        try {
          await expectRedWithDiagnostic(repo, gate, 'hook-go-black-box', whiteBox);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    })),
  ],
};
