import { describe, it } from 'bun:test';
import 'should';
import { UnwrapError } from '../../src/lib/error.js';

describe('UnwrapError', () => {
  it('should expose the canonical result mismatch details', () => {
    // Arrange
    const message = 'Failed to unwrap';

    // Act
    const actual = new UnwrapError(message, 'result', 'Expected Ok got Error');

    // Assert
    actual.should.be.instanceof(Error);
    actual.name.should.equal('UnwrapError');
    actual.message.should.equal(message);
    actual.monadType.should.equal('result');
    actual.type.should.equal('Expected Ok got Error');
  });

  it('should expose the canonical option mismatch details', () => {
    // Arrange
    const expected = 'Expected Some got None';

    // Act
    const error = new UnwrapError('Failed to unwrap', 'option', expected);
    const actual = error.type;

    // Assert
    error.monadType.should.equal('option');
    actual.should.equal(expected);
  });
});
