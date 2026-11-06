// Parent-owned tooling standards are deliberately absent.
export const topics = [
  'datetime',
  'domain-driven-design',
  'functional-practices',
  'software-design-philosophy',
  'solid-principles',
  'stateless-oop-di',
  'testing',
  'three-layer-architecture',
  'utilities',
  'validation',
  'wire-format',
] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-standards-inventory',
      description: 'All eleven agnostic standards and their thin triggers exist.',
      kind: 'baseline',
      async run(repo: any) {
        for (const topic of topics) {
          if ((await repo.glob(`docs/standards/${topic}/index.md`)).length !== 1) {
            throw new Error(`missing shared standard index: ${topic}`);
          }
          if ((await repo.glob(`.claude/skills/${topic}/SKILL.md`)).length !== 1) {
            throw new Error(`missing shared standard skill: ${topic}`);
          }
        }
      },
    },
  ],
};
