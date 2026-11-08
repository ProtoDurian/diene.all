import { expectSuccess } from './lib/exec.ts';
import { expectGreen, expectRedWithDiagnostic } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-consumer-test.sh';
const dropped = 'lib/problem/type_uri.go';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-lib-consumer-test-green',
      description:
        'A fresh module consumes the go mod download pack of HEAD through a local replace: imports, builds, vets and tests.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-lib-consumer-test');
      },
    },
    {
      name: 'mutation-go-lib-consumer-test-caught',
      description:
        'Dropping a package-declared file from the commit leaves it out of the pack; the consumer test turns red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Go packs committed files only, so the drop must land in a commit.
        await expectSuccess(
          repo,
          `git rm -q --cached -- ${dropped} && git -c user.name=Probe -c user.email=probe@example.invalid ` +
            '-c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm probe-drop',
        );
        await expectRedWithDiagnostic(
          repo,
          gate,
          'go-lib-consumer-test',
          /-github\.com\/\S+\/lib\/problem\/type_uri\.go[\s\S]*does not ship exactly the files its package manifest declares/,
        );
      },
    },
  ],
};
