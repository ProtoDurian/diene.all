import { withCleanProbeState } from './lib/helpers.ts';

const CD = '.github/workflows/cd.yaml';
const REUSABLE = '.github/workflows/⚡reusable-publish.yaml';
const SCRIPT = './scripts/ci/publish.sh';

// Caller job -> reusable workflow -> every repository script its steps run.
async function wiringViolation(repo: any): Promise<string | undefined> {
  const caller = Bun.YAML.parse(await repo.read(CD)) as any;
  const jobs = Object.values(caller?.jobs ?? {}) as any[];
  if (!jobs.some(job => job?.uses === `./${REUSABLE}`)) {
    return `${CD} has no job calling ${REUSABLE}`;
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
      name: 'baseline-publish-workflow-wiring-green',
      description: 'CD reaches the guarded credentialed publish script through the reusable workflow',
      kind: 'baseline',
      async run(repo: any) {
        const violation = await wiringViolation(repo);
        if (violation) {
          throw new Error(`publish-workflow-wiring: ${violation}`);
        }
      },
    },
    {
      name: 'mutation-publish-workflow-wiring-caught',
      description: 'the wiring check fails once the reusable workflow points at a missing script',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [REUSABLE], async () => {
          if (await wiringViolation(repo)) {
            throw new Error('publish-workflow-wiring: wiring already broken before sabotage');
          }
          await repo.patch(REUSABLE, { find: SCRIPT, replace: './scripts/ci/publish-missing.sh' });
          const violation = await wiringViolation(repo);
          if (!violation?.startsWith('missing script')) {
            throw new Error(`publish-workflow-wiring: wiring survived sabotage (${violation ?? 'green'})`);
          }
        });
      },
    },
  ],
};
