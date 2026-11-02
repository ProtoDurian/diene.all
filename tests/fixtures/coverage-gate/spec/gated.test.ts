import { describe, it } from 'bun:test';
import should from 'should';
import { alwaysMeasured, measuredOnlyWhileTheSuiteRuns } from '../src/gated';

const sabotaged = process.env.COVERAGE_GATE_SABOTAGE === '1';
const gated = sabotaged ? it.skip : it;

describe('coverage gate fixture', () => {
  it('should cover the baseline function in every run', () => {
    const input = 1;
    const expected = 2;

    const actual = alwaysMeasured(input);

    should(actual).equal(expected);
  });

  gated('should cover the gated function unless the run is sabotaged', () => {
    const input = 2;
    const expected = 4;

    const actual = measuredOnlyWhileTheSuiteRuns(input);

    should(actual).equal(expected);
  });
});
