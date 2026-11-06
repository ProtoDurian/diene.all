import { describe, it } from 'bun:test';
import 'should';
import { Deduper } from '../../src/lib/unique';

describe('Deduper.unique', () => {
  it.each([
    { label: 'primitives', items: [1, 2, 2, 3, 1, 3], expected: [1, 2, 3] },
    { label: 'strings', items: ['a', 'b', 'a', 'c', 'b'], expected: ['a', 'b', 'c'] },
    { label: '+0 and -0', items: [0, -0, 0], expected: [0] },
  ])('should keep the first occurrence of $label', ({ items, expected }) => {
    // Arrange
    const { unique } = new Deduper();

    // Act
    const actual = (items as readonly unknown[]).filter(unique);

    // Assert
    actual.should.deepEqual(expected);
  });

  it('should treat NaN as equal to NaN', () => {
    // Arrange
    const deduper = new Deduper();

    // Act
    const actual = [Number.NaN, Number.NaN, 1].filter(deduper.unique);

    // Assert
    actual.length.should.equal(2);
    Number.isNaN(actual[0]).should.be.true();
  });

  it('should distinguish objects by reference', () => {
    // Arrange
    const shared = { id: 1 };
    const other = { id: 1 };
    const deduper = new Deduper();

    // Act
    const actual = [shared, shared, other].filter(deduper.unique);

    // Assert
    actual.length.should.equal(2);
    (actual[0] === shared && actual[1] === other).should.be.true();
  });
});
