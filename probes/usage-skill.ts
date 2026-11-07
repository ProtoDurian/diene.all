const SKILL_DIR = 'packages/diene_interfaces/skills/diene-interfaces-usage';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-usage-skill-present',
      description: 'the shipped usage skill and its assets exist in the package',
      kind: 'baseline',
      async run(repo: any) {
        const skill = await repo.read(`${SKILL_DIR}/SKILL.md`);
        const name = skill.match(/^---\n[\s\S]*?^name:\s*(\S+)\s*$[\s\S]*?^---$/m)?.[1];
        if (name !== 'diene-interfaces-usage') {
          throw new Error(`usage-skill: SKILL.md frontmatter name is ${name ?? '(none)'}`);
        }
        if ((await repo.glob(`${SKILL_DIR}/patterns.md`)).length !== 1) {
          throw new Error('usage-skill: patterns.md asset is missing');
        }
      },
    },
  ],
};
