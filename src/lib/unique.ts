class Deduper {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  // An arrow field, so `array.filter(deduper.unique)` works unbound.
  readonly unique = <T>(value: T, index: number, array: readonly T[]): boolean =>
    array.findIndex(candidate => candidate === value || (Number.isNaN(candidate) && Number.isNaN(value))) === index;
}

export { Deduper };
