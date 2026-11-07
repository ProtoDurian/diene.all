import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-module-path.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-module-path-green',
      description: 'The declared Go module path is the mirror repository path.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-lib-module-path');
      },
    },
    {
      name: 'mutation-go-lib-module-path-caught',
      description: 'Changing only the declared module path turns the module-path gate red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('go.mod', {
          find: 'module github.com/ProtoDurian/diene.go-interfaces',
          replace: 'module github.com/ProtoDurian/diene.go-wrong',
        });
        await expectRedWithDiagnostic(
          repo,
          gate,
          'go-lib-module-path',
          /module path 'github\.com\/ProtoDurian\/diene\.go-wrong' must be/,
        );
      },
    },
  ],
};
