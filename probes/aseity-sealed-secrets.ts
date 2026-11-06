import { expectGreen, expectRedBecause } from './lib/helpers.ts';

type ProbeRepo = {
  exec(
    command: string,
    options?: { timeoutMs?: number },
  ): Promise<{ exitCode: number; stdout: string; stderr: string }>;
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
};

const command = 'nix develop .#ci -c ./scripts/validate/secrets.sh';
const sealedFile = 'secrets/production.yaml';
const sealedLine = /^([A-Z0-9_]+): (ENC\[[^\]]+\])$/m;

async function firstSealedLine(repo: ProbeRepo): Promise<{ text: string; key: string; value: string }> {
  const text = await repo.read(sealedFile);
  const match = sealedLine.exec(text);
  if (!match?.[1] || !match[2])
    throw new Error(`aseity-sealed-secrets: ${sealedFile} has no sealed KEY: ENC[...] line`);
  return { text, key: match[1], value: match[2] };
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-sealed-secrets-green',
      description: 'Every secret is sealed, and sealed keys, OpenTofu sensitive variables and Worker secrets agree.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectGreen(repo, command, 'aseity-sealed-secrets');
      },
    },
    {
      name: 'mutation-aseity-sealed-secrets-plain-value-caught',
      description: 'A sealed value replaced by plain text turns the check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const { text, key, value } = await firstSealedLine(repo);
        await repo.write(sealedFile, text.replace(`${key}: ${value}`, `${key}: probe-plain-value`));
        await expectRedBecause(repo, command, 'aseity-sealed-secrets', [`${key} is not sealed`], {
          forbidden: ['Sealed secrets hold'],
        });
      },
    },
    {
      name: 'mutation-aseity-sealed-secrets-one-sided-key-caught',
      description: 'A key sealed in secrets/ with no matching OpenTofu sensitive variable turns the check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        // Reuse a real sealed value so the file stays well formed and no secret-shaped literal ships.
        const { text, value } = await firstSealedLine(repo);
        await repo.write(sealedFile, `PROBE_ONE_SIDED: ${value}\n${text}`);
        await expectRedBecause(
          repo,
          command,
          'aseity-sealed-secrets',
          ['sealed but not a sensitive variable in infra/tofu: PROBE_ONE_SIDED'],
          { forbidden: ['Sealed secrets hold', 'is not sealed'] },
        );
      },
    },
  ],
};
