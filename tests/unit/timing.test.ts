import { describe, it } from 'bun:test';
import should from 'should';
import { Timing } from '../../src/lib/timing';

describe('Timing.sleep', () => {
  it.each([{ seconds: 0 }, { seconds: 0.01 }])('should resolve to undefined after $seconds s', async ({ seconds }) => {
    // Arrange
    const timing = new Timing();

    // Act
    const actual = await timing.sleep(seconds);

    // Assert
    should(actual).be.undefined();
  });

  it.each([
    { seconds: -1, label: 'negative' },
    { seconds: Number.NaN, label: 'NaN' },
    { seconds: Number.POSITIVE_INFINITY, label: 'infinite' },
  ])('should reject a $label delay with a RangeError', async ({ seconds }) => {
    // Arrange
    const timing = new Timing();

    // Act
    const actual = timing.sleep(seconds);

    // Assert
    await actual.should.be.rejectedWith(RangeError);
  });
});

describe('Timing.noop', () => {
  it('should return undefined', () => {
    // Arrange
    const timing = new Timing();

    // Act
    const actual = timing.noop();

    // Assert
    should(actual).be.undefined();
  });
});
