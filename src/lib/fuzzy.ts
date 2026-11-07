class FuzzyMatcher {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  fuzzyIncludes(a: string, b: string): boolean {
    return a.toLowerCase().includes(b.toLowerCase());
  }
}

export { FuzzyMatcher };
