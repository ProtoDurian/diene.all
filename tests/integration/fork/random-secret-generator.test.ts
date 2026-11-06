import { describe, it } from 'bun:test';
import 'should';
import { RandomSecretGenerator } from '../../../src/adapters/fork/random-secret-generator';

describe('RandomSecretGenerator', () => {
  it('should make a fresh 256-bit url-safe secret each time', () => {
    // Arrange
    const subject = new RandomSecretGenerator();

    // Act
    const actual = [subject.generate(), subject.generate()];

    // Assert
    actual[0]?.should.match(/^[A-Za-z0-9_-]{43}$/);
    actual[0]?.should.not.equal(actual[1]);
  });
});
