const TEMPLATE = 'diene/dart-lib';
const MATRIX: Record<string, 'gate' | 'smoke' | 'presence'> = {
  'dart-format': 'gate',
  'dart-analyze': 'gate',
  'unit-tests': 'gate',
  'c0-fixture-harness': 'gate',
  'unit-coverage-ledger': 'gate',
  'testhelper-meta-contract': 'gate',
  'testhelper-meta-coverage-ledger': 'gate',
  'conditional-meta-activation': 'gate',
  'deadcode-whole-package': 'gate',
  'deadcode-production-only': 'gate',
  'pub-workspace-metadata-validator': 'gate',
  'publish-archive-contents': 'gate',
  'consumer-test': 'gate',
  'pana-score': 'gate',
  'publish-version-guard': 'gate',
  'publish-tag-policy': 'gate',
  'automated-publishing-credential-policy': 'gate',
  'publish-command-policy': 'gate',
  'package-validate-workflow-wiring': 'gate',
  'publish-workflow-wiring': 'gate',
  'dart-tool-inventory': 'smoke',
  'pub-workspace-resolution': 'smoke',
  'sample-execution-consumption': 'smoke',
  'publish-dry-run': 'smoke',
  'usage-skill': 'presence',
  'probe-inventory': 'presence',
};

function inventoryViolation(features: unknown, modules: Map<string, string>): string | undefined {
  if (!Array.isArray(features) || features.length === 0) {
    return 'features.json is not a non-empty array';
  }
  for (const row of features) {
    if (typeof row?.template !== 'string' || typeof row?.name !== 'string' || typeof row?.class !== 'string') {
      return `malformed row ${JSON.stringify(row)}`;
    }
    if (!modules.has(row.name)) {
      return `row ${row.template}#${row.name} has no probes/${row.name}.ts`;
    }
  }
  const declared = new Set(features.map((row: any) => row.name));
  for (const name of modules.keys()) {
    if (!declared.has(name)) {
      return `probe module ${name} has no row`;
    }
  }
  const own = features.filter((row: any) => row.template === TEMPLATE);
  const ownNames = own.map((row: any) => row.name).sort();
  const expected = Object.keys(MATRIX).sort();
  if (JSON.stringify(ownNames) !== JSON.stringify(expected)) {
    return `${TEMPLATE} rows ${ownNames.join(',')} != matrix ${expected.join(',')}`;
  }
  for (const row of own) {
    if (row.class !== MATRIX[row.name]) {
      return `${row.name} is classed ${row.class}, the matrix says ${MATRIX[row.name]}`;
    }
    const hasMutation = /kind:\s*'mutation'/.test(modules.get(row.name) ?? '');
    if (hasMutation !== (row.class === 'gate')) {
      return `${row.name} is a ${row.class} but ${hasMutation ? 'ships' : 'lacks'} a mutation`;
    }
  }
  return undefined;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-probe-inventory-consistent',
      description: 'features.json and probes/ match 1:1 and the dart-lib rows match the classed matrix',
      kind: 'baseline',
      async run(repo: any) {
        const modules = new Map<string, string>();
        for (const path of await repo.glob('probes/*.ts')) {
          modules.set(path.replace(/^probes\//, '').replace(/\.ts$/, ''), await repo.read(path));
        }
        const violation = inventoryViolation(JSON.parse(await repo.read('probes/features.json')), modules);
        if (violation) {
          throw new Error(`probe-inventory: ${violation}`);
        }
      },
    },
  ],
};
