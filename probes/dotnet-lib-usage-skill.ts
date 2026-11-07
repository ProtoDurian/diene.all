import { definePresence } from './lib/definition.ts';

const SKILL = 'skills/diene-dotnet-problems-usage/SKILL.md';

export default definePresence({
  sandbox: { snapshot: 'git' },
  baseline: {
    name: 'presence-dotnet-lib-usage-skill',
    description: 'The shipped usage skill exists and its frontmatter names it.',
    async run(repo: any) {
      const frontmatter = (await repo.read(SKILL)).match(/^---\n([\s\S]*?)\n---/);
      const name = frontmatter?.[1].match(/^name:\s*(.+)$/m)?.[1]?.trim();
      if (name !== 'diene-dotnet-problems-usage') {
        throw new Error(`usage skill name mismatch: ${name ?? 'missing'}`);
      }
    },
  },
});
