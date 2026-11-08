import { breakExampleOutput } from './lib/go-library.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-examples.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-examples-green',
      description: 'Every Example function compiles and its checked output matches.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-lib-examples');
      },
    },
    {
      name: 'mutation-go-lib-examples-caught',
      description: 'A broken Example output turns the examples gate red.',
      kind: 'mutation',
      async run(repo: any) {
        await breakExampleOutput(repo);
        await expectRedWithDiagnostic(
          repo,
          gate,
          'go-lib-examples',
          /--- FAIL: Example[A-Za-z0-9_]+[\s\S]*probe-wrong-output/,
        );
      },
    },
  ],
};
