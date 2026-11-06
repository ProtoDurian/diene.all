import { describe, it } from 'bun:test';
import 'should';
import { WireDurationConverter } from '../../src/lib/duration';

describe('WireDurationConverter', () => {
  it.each([
    ['PT10S', 10_000],
    ['PT60S', 60_000],
    ['PT1M', 60_000],
    ['PT0.5S', 500],
  ])('should convert %s to %d milliseconds', (input, expected) => {
    // Arrange
    const converter = new WireDurationConverter();

    // Act
    const actual = converter.toMilliseconds(input);

    // Assert
    actual.should.equal(expected);
  });

  it.each([
    ['a zero duration', 'PT0S'],
    ['a non-ISO string', '10s'],
    ['a negative duration', '-PT1S'],
  ])('should throw a RangeError on %s', (_label, input) => {
    // Arrange
    const converter = new WireDurationConverter();

    // Act
    const act = () => converter.toMilliseconds(input);

    // Assert
    act.should.throw(RangeError);
  });
});
