import { expectGreen, expectRedBecause } from './lib/helpers.ts';

type ProbeRepo = {
  exec(
    command: string,
    options?: { timeoutMs?: number },
  ): Promise<{ exitCode: number; stdout: string; stderr: string }>;
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
};

const command = 'nix develop .#ci -c ./scripts/validate/tofu.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-tofu-validate-green',
      description: 'The OpenTofu configuration for Cloudflare, Neon and Tigris is formatted and validates.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectGreen(repo, command, 'aseity-tofu-validate');
      },
    },
    {
      name: 'mutation-aseity-tofu-validate-caught',
      description: 'An output that references an undeclared variable turns tofu validate red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const path = 'infra/tofu/outputs.tf';
        await repo.write(
          path,
          `${await repo.read(path)}\noutput "probe_undeclared" {\n  value = var.probe_undeclared\n}\n`,
        );
        await expectRedBecause(repo, command, 'aseity-tofu-validate', ['Reference to undeclared input variable'], {
          forbidden: ['OpenTofu configuration is valid'],
        });
      },
    },
  ],
};
