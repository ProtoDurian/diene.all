import { describe, it } from 'bun:test';
import 'should';
import { Hasher } from '../../src/lib/hash';

describe('Hasher.sha256', () => {
  it.each([
    { input: '', expected: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' },
    { input: 'abc', expected: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' },
    {
      input: 'The quick brown fox jumps over the lazy dog',
      expected: 'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592',
    },
    { input: 'é', expected: '4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c' },
  ])('should hash "$input" to its known lowercase hex digest', async ({ input, expected }) => {
    // Arrange
    const hasher = new Hasher();

    // Act
    const actual = await hasher.sha256(input);

    // Assert
    actual.should.equal(expected);
  });
});
