import { describe, it } from 'bun:test';
import 'should';
import { FuzzyMatcher } from '../../src/lib/fuzzy';

describe('FuzzyMatcher.fuzzyIncludes', () => {
  it.each([
    { a: 'Hello World', b: 'world', expected: true },
    { a: 'Hello World', b: 'HELLO', expected: true },
    { a: 'Hello World', b: 'lo Wo', expected: true },
    { a: 'Hello World', b: 'planet', expected: false },
    { a: 'abc', b: '', expected: true },
    { a: '', b: 'a', expected: false },
    { a: '', b: '', expected: true },
  ])('should return $expected for needle "$b" in haystack "$a"', ({ a, b, expected }) => {
    // Arrange
    const matcher = new FuzzyMatcher();

    // Act
    const actual = matcher.fuzzyIncludes(a, b);

    // Assert
    actual.should.equal(expected);
  });
});
