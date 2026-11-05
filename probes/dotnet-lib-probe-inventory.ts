import { definePresence } from './lib/definition.ts';

export default definePresence({
  sandbox: { snapshot: 'git' },
  baseline: {
    name: 'presence-dotnet-lib-probe-inventory',
    description: 'Every class-bearing diene/dotnet-lib feature row has its probe module.',
    async run(repo: any) {
      const rows = JSON.parse(await repo.read('probes/features.json')).filter(
        (row: any) => row.template === 'diene/dotnet-lib',
      );
      if (rows.length === 0) {
        throw new Error('features.json declares no diene/dotnet-lib rows');
      }
      for (const row of rows) {
        if (!['gate', 'smoke', 'presence'].includes(row.class)) {
          throw new Error(`${row.name} has no evidence class`);
        }
        if ((await repo.glob(`probes/${row.name}.ts`)).length !== 1) {
          throw new Error(`${row.name} has no probe module`);
        }
      }
    },
  },
});
