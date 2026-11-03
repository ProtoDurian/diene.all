export function alwaysMeasured(value: number): number {
  return value + 1;
}

export function measuredOnlyWhileTheSuiteRuns(value: number): number {
  return value * 2;
}
