import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const hook = 'nix develop --no-write-lock-file .#ci -c pre-commit run a-rule-ids';
const planted = 'rule-ids-probe.txt';

async function plant(repo: any, fixture: string): Promise<void> {
  await repo.write(planted, await repo.read(`tests/fixtures/rule-ids/${fixture}.txt`));
  const staged = await repo.exec(`git add ${planted}`);
  if (staged.exitCode !== 0) {
    throw new Error(`could not stage the rule-ids fixture: ${staged.stderr || staged.stdout}`);
  }
}

async function unplant(repo: any): Promise<void> {
  await repo.exec(`git rm -f -q --cached -- ${planted}`);
  await repo.exec(`git clean -fq -- ${planted}`);
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-rule-ids-green',
      description:
        'No shipped file carries a corpus rule ID, and the passing fixture (product names, near misses) passes.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, `${hook} --all-files`, 'rule-ids');
        try {
          await plant(repo, 'pass');
          await expectGreen(repo, `${hook} --files ${planted}`, 'rule-ids');
        } finally {
          await unplant(repo);
        }
      },
    },
    {
      name: 'mutation-rule-ids-caught',
      description: 'The failing fixture in a shipped file must be refused for its corpus rule IDs.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        try {
          await plant(repo, 'fail');
          await expectRedBecause(repo, `${hook} --all-files`, 'rule-ids', [
            `${planted}:1: corpus rule ID`,
            `${planted}:2: corpus rule ID`,
          ]);
        } finally {
          await unplant(repo);
        }
      },
    },
  ],
};
