import { restoreProbeState } from './lib/helpers.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c task test:int:coverage';

async function modulePath(repo: any): Promise<string> {
  const module = (await repo.read('go.mod')).match(/^module\s+(\S+)/m)?.[1];
  if (!module) {
    throw new Error('Go module path is missing');
  }
  return module;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-integration-coverage-scoped',
      description:
        'The integration coverprofile contains only adapter packages at threshold, or the tier is empty with no adapters.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'integration-coverage-scope');
      },
    },
    {
      name: 'mutation-integration-coverage-caught',
      description: 'An adapter source the profile never measures must turn the integration ledger red.',
      kind: 'mutation',
      async run(repo: any) {
        const module = await modulePath(repo);
        // A fully covered adapter plus a file with no statements: only the derived source set catches the second.
        await repo.write('adapters/probe/probe.go', 'package probe\n\nfunc Probe() int { return 1 }\n');
        await repo.write('adapters/probe/probe_uncovered.go', 'package probe\n\ntype ProbeUncovered struct{}\n');
        await repo.write(
          'tests/int/probe/probe_test.go',
          `package probe_test\n\nimport (\n\t"testing"\n\n\t"${module}/adapters/probe"\n)\n\nfunc TestProbe(t *testing.T) {\n\tif probe.Probe() != 1 {\n\t\tt.Fatal("probe")\n\t}\n}\n`,
        );
        try {
          await expectRedWithDiagnostic(
            repo,
            gate,
            'integration-coverage-scope',
            /int coverage is missing 'adapters\/probe\/probe_uncovered\.go'/,
          );
        } finally {
          await restoreProbeState(repo, ['adapters/probe', 'tests/int/probe']);
        }
      },
    },
    {
      name: 'mutation-integration-untested-adapter-caught',
      description: 'An adapter with no integration test must turn the integration ledger red instead of an empty tier.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.write('adapters/probe/probe.go', 'package probe\n\nfunc Probe() int { return 1 }\n');
        try {
          // No int tests at all (empty tier) fails on the missing test tree; beside other adapters it is unmeasured.
          await expectRedWithDiagnostic(
            repo,
            gate,
            'integration-coverage-scope',
            /lstat \.\/tests\/int\/: no such file or directory|int coverage is missing 'adapters\/probe\/probe\.go'/,
          );
        } finally {
          await restoreProbeState(repo, ['adapters/probe']);
        }
      },
    },
  ],
};
