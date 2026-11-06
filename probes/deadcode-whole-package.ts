import { expectGreen, expectRedBecause, withCleanProbeState } from './lib/helpers.ts';

const DEADCODE = 'nix develop .#ci -c ./scripts/ci/deadcode.sh';
const CLASS_DECLARATION = /^(?:final |base |sealed |abstract )*class \w+[^{\n]*\{\n/m;

async function findClassFile(repo: any): Promise<string> {
  for (const candidate of (await repo.glob('packages/*/lib/src/*.dart')).sort()) {
    if (CLASS_DECLARATION.test(await repo.read(candidate))) {
      return candidate;
    }
  }
  throw new Error('deadcode-whole-package: no shipped class declaration found under lib/src');
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: { post: ['nix develop .#ci -c dart pub get --offline'] },
  probes: [
    {
      name: 'baseline-deadcode-whole-package-green',
      description: 'both no-exclusion dead-code views are clean',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, DEADCODE, 'deadcode-whole-package');
      },
    },
    {
      name: 'mutation-deadcode-whole-package-caught',
      description: 'the whole-package view flags an unused private member of a used shipped class',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const target = await findClassFile(repo);
        await withCleanProbeState(repo, [target], async () => {
          const source = await repo.read(target);
          await repo.write(
            target,
            source.replace(CLASS_DECLARATION, match => `${match}  int _probeUnused() => 1;\n\n`),
          );
          await expectRedBecause(repo, DEADCODE, 'deadcode-whole-package', ['unused method _probeUnused'], {
            forbidden: ['Production dead-code pass'],
          });
        });
      },
    },
  ],
};
