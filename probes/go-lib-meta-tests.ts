import { flipMetaAssertion } from './lib/go-library.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/local/test.sh meta false false';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-meta-tests-green',
      description: 'The TestHelper meta tests pass.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-lib-meta-tests');
      },
    },
    {
      name: 'mutation-go-lib-meta-tests-caught',
      description: 'A flipped meta assertion turns the meta tier red.',
      kind: 'mutation',
      async run(repo: any) {
        const mutated = await flipMetaAssertion(repo);
        await expectRedWithDiagnostic(repo, gate, 'go-lib-meta-tests', mutated.failure);
      },
    },
  ],
};
