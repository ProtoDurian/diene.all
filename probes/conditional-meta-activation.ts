import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const REUSABLE_TEST = '.github/workflows/⚡reusable-test.yaml';
const UPLOAD_ACTION = 'actions/upload-artifact@';
const GUARD = "hashFiles(format('reports/{0}/lcov.info', inputs.mode)) != ''";
const INACTIVE_META =
  'nix develop .#ci -c bash -c \'TEST_HELPER_PATH=lib/probe_absent_helper.dart ./scripts/ci/test.sh meta coverage | grep -F "Meta tier inactive"\'';
// No real TestHelper here, so a shipped lib file stands in for one.
const HELPER_WITHOUT_SUITE =
  'nix develop .#ci -c env TEST_HELPER_PATH=lib/diene_core_utils.dart META_TEST_PATH=test/probe_absent_meta ./scripts/ci/test.sh meta coverage';

// Every artifact upload must be skipped when the run produced no ledger.
function uploadsAreConditional(source: string): string | undefined {
  let document: any;
  try {
    document = Bun.YAML.parse(source);
  } catch (error) {
    return `workflow does not parse: ${String(error)}`;
  }
  const steps = Object.values(document?.jobs ?? {}).flatMap((job: any) => (Array.isArray(job?.steps) ? job.steps : []));
  const uploads = steps.filter((step: any) => typeof step?.uses === 'string' && step.uses.startsWith(UPLOAD_ACTION));
  if (uploads.length === 0) {
    return 'no coverage artifact upload step found';
  }
  const unguarded = uploads.filter((step: any) => typeof step.if !== 'string' || !step.if.includes(GUARD));
  if (unguarded.length > 0) {
    return `coverage artifact upload is unconditional: ${unguarded.map((step: any) => step.name).join(', ')}`;
  }
  return undefined;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-conditional-meta-activation-green',
      description:
        'without a TestHelper the meta tier is a no-op with no ledger, a helper without its meta suite fails, and CI uploads only an existing ledger',
      kind: 'baseline',
      async run(repo: any) {
        await withCleanProbeState(repo, ['reports/meta'], async () => {
          await expectGreen(repo, INACTIVE_META, 'conditional-meta-activation');
          if ((await repo.glob('reports/meta/**')).length !== 0) {
            throw new Error('conditional-meta-activation: the inactive meta tier still emitted a ledger');
          }
        });
        await expectRedBecause(repo, HELPER_WITHOUT_SUITE, 'conditional-meta-activation', [
          'ships without its meta suite',
        ]);
        const violation = uploadsAreConditional(await repo.read(REUSABLE_TEST));
        if (violation) {
          throw new Error(`conditional-meta-activation: ${violation}`);
        }
      },
    },
    {
      name: 'mutation-conditional-meta-activation-caught',
      description: 'the upload policy check fails once the coverage artifact upload loses its ledger guard',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await withCleanProbeState(repo, [REUSABLE_TEST], async () => {
          const source = await repo.read(REUSABLE_TEST);
          if (uploadsAreConditional(source)) {
            throw new Error('conditional-meta-activation: policy already broken before sabotage');
          }
          const lines = source.split('\n');
          const uploadAt = lines.findIndex((line: string) => line.includes(`uses: ${UPLOAD_ACTION}`));
          const guardAt = lines.findIndex(
            (line: string, index: number) => index > uploadAt - 3 && index < uploadAt && line.includes(GUARD),
          );
          if (uploadAt === -1 || guardAt === -1) {
            throw new Error('conditional-meta-activation: no guarded upload step to sabotage');
          }
          lines.splice(guardAt, 1);
          await repo.write(REUSABLE_TEST, lines.join('\n'));
          const violation = uploadsAreConditional(await repo.read(REUSABLE_TEST));
          if (!violation?.includes('unconditional')) {
            throw new Error(`conditional-meta-activation: upload policy survived sabotage (${violation ?? 'green'})`);
          }
        });
      },
    },
  ],
};
