import { expectGreen, expectRed } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-otel-sit-green',
      description:
        'A host wired by AddAtomiOtel exports traces, metrics and logs over OTLP/HTTP to a loopback receiver on 4318.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c task test:sit', 'dotnet-otel-sit', 600000);
      },
    },
    {
      name: 'mutation-dotnet-otel-sit-caught',
      description: 'Switching the exporter off http/protobuf turns the SIT tier red.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-unit-tests',
        'dotnet-unit-coverage',
        'dotnet-multi-project-coverage',
        'dotnet-coverage-artifact-scope',
        'dotnet-lib-coverage-ledger',
        'dotnet-lib-testhelper-contract',
      ],
      async run(repo: any) {
        await repo.patch('Lib/OtelHostExtensions.cs', {
          find: 'target.Protocol = OtlpExportProtocol.HttpProtobuf;',
          replace: 'target.Protocol = OtlpExportProtocol.Grpc;',
        });
        await expectRed(repo, 'nix develop .#ci -c task test:sit', 'dotnet-otel-sit', 600000);
      },
    },
  ],
};
