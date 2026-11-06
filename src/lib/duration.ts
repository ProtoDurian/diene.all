import { parseWireDuration } from '@atomicloud/diene.core-utils';

const FIXED_DURATION_ERROR = 'Duration must be a positive, fixed-length canonical ISO 8601 duration';

class WireDurationConverter {
  constructor(private readonly parse: typeof parseWireDuration = parseWireDuration) {}

  toMilliseconds(value: string): number {
    const milliseconds = this.parse(value).total({ unit: 'milliseconds' });
    if (!Number.isFinite(milliseconds) || milliseconds <= 0) throw new RangeError(FIXED_DURATION_ERROR);
    return milliseconds;
  }
}

export { FIXED_DURATION_ERROR, WireDurationConverter };
