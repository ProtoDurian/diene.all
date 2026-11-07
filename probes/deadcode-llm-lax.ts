import { expectGreen } from './lib/go.ts';

const passes = [
  'whole-repository staticcheck',
  'whole-repository deadcode',
  'production staticcheck',
  'production deadcode',
];
const evidence = passes.map(pass => `grep -qF '## pass complete: ${pass} (' reports/deadcode-llm.txt`).join(' && ');
// Remove the old report so a stale one cannot pass.
const gate = `nix develop .#ci -c bash -lc "rm -f reports/deadcode-llm.txt && ./scripts/local/deadcode.sh lax && ${evidence}"`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-lax-report-green',
      description: 'The LLM-lax deadcode feed emits a nonblocking review artifact recording all four scanner passes.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'deadcode-llm-lax');
      },
    },
  ],
};
