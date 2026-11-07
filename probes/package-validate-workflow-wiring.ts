import { withCleanProbeState } from './lib/helpers.ts';

const CI = '.github/workflows/ci.yaml';
const REUSABLE = '.github/workflows/⚡reusable-package-validate.yaml';
const SCRIPT = './scripts/ci/package-validate.sh';

// Caller job -> reusable workflow -> every repository script its steps run.
async function wiringViolation(repo: any): Promise<string | undefined> {
  const caller = Bun.YAML.parse(await repo.read(CI)) as any;
  const jobs = Object.values(caller?.jobs ?? {}) as any[];
  if (!jobs.some(job => job?.uses === `./${REUSABLE}`)) {
    return `${CI} has no job calling ${REUSABLE}`;
  }
  if ((await repo.glob(REUSABLE)).length !== 1) {
    return `missing reusable workflow ${REUSABLE}`;
  }
  const reusable = Bun.YAML.parse(await repo.read(REUSABLE)) as any;
  const runs = Object.values(reusable?.jobs ?? {})
    .flatMap((job: any) => (Array.isArray(job?.steps) ? job.steps : []))
    .map((step: any) => (typeof step?.run === 'string' ? step.run : ''));
  const scripts = runs.flatMap(run => run.match(/\.\/scripts\/[\w./-]+\.sh/g) ?? []);
  for (const script of scripts) {
    if ((await repo.glob(script.slice(2))).length !== 1) {
      return `missing script ${script}`;
    }
  }
  if (!scripts.includes(SCRIPT)) {
    return `${REUSABLE} does not run ${SCRIPT}`;
  }
  return undefined;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-package-validate-workflow-wiring-green',
      description: 'CI reaches the package validator through the reusable workflow',
      kind: 'baseline',
      async run(repo: any) {
        const violation = await wiringViolation(repo);
        if (violation) {
          throw new Error(`package-validate-workflow-wiring: ${violation}`);
        }
      },
    },
    {
      name: 'mutation-package-validate-workflow-wiring-caught',
      description: 'the wiring check fails once the reusable workflow points at a missing script',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [REUSABLE], async () => {
          if (await wiringViolation(repo)) {
            throw new Error('package-validate-workflow-wiring: wiring already broken before sabotage');
          }
          await repo.patch(REUSABLE, { find: SCRIPT, replace: './scripts/ci/package-validate-missing.sh' });
          const violation = await wiringViolation(repo);
          if (!violation?.startsWith('missing script')) {
            throw new Error(`package-validate-workflow-wiring: wiring survived sabotage (${violation ?? 'green'})`);
          }
        });
      },
    },
  ],
};
