import { expectGreen } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-build-artifact-green',
      description: 'The build task compiles every package of the library module.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc 'task build && go list ./... >/dev/null'",
          'build-artifact',
        );
      },
    },
  ],
};
