import { expectGreen, expectRed } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description: 'The demo consumer wires the otel engine onto a real host with in-memory seams.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c task test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Changing the demo identity turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-integration-coverage',
        'dotnet-deadcode-all',
        'dotnet-deadcode-production',
        'dotnet-dev',
        'dotnet-run',
        'dotnet-preview',
      ],
      async run(repo: any) {
        await repo.patch('App/OtelDemo.cs', {
          find: '.Create("lapras", "atomi", "dotnet-otel-demo", "app", "1.0.0")',
          replace: '.Create("pichu", "atomi", "dotnet-otel-demo", "app", "1.0.0")',
        });
        await expectRed(repo, 'nix develop .#ci -c task test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
