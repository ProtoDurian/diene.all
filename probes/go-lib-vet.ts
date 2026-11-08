import { plantVetMisuse } from './lib/go-library.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-vet.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-vet-green',
      description: 'go vet finds no misuse in the library.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-lib-vet');
      },
    },
    {
      name: 'mutation-go-lib-vet-caught',
      description: 'A vet-detectable format misuse turns the vet gate red.',
      kind: 'mutation',
      async run(repo: any) {
        await plantVetMisuse(repo);
        await expectRedWithDiagnostic(
          repo,
          gate,
          'go-lib-vet',
          /probe_vet\.go:\d+:\d+: fmt\.Sprintf format %d has arg "not-an-integer" of wrong type string/,
        );
      },
    },
  ],
};
