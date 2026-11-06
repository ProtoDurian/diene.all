import { describe, it } from 'bun:test';
import 'should';
import { z } from 'zod';
import { ConfigValidationError, ConfigValidator } from '../../src/lib/validator.js';

const validator = new ConfigValidator();

const caught = (act: () => unknown): ConfigValidationError => {
  try {
    act();
  } catch (error) {
    if (error instanceof ConfigValidationError) return error;
    throw error;
  }
  throw new Error('expected a ConfigValidationError');
};

describe('ConfigValidator.validate', () => {
  it('should return the parsed value when valid', () => {
    // Arrange
    const schema = z.object({ port: z.number() });

    // Act
    const actual = validator.validate(schema, { port: 8080 });

    // Assert
    actual.should.deepEqual({ port: 8080 });
  });

  it.each([
    { label: 'a nested failure by dotted path', value: { server: { port: 'nope' } }, pattern: /^server\.port: / },
    { label: 'a root failure as (root)', value: 'not-an-object', pattern: /^\(root\): / },
  ])('should label $label', ({ value, pattern }) => {
    // Arrange
    const schema = z.object({ server: z.object({ port: z.number() }) });

    // Act
    const error = caught(() => validator.validate(schema, value));

    // Assert
    error.name.should.equal('ConfigValidationError');
    (error.issues[0] ?? '').should.match(pattern);
  });

  it('should aggregate every issue into one readable message', () => {
    // Arrange
    const schema = z.object({ port: z.number(), host: z.string() });

    // Act
    const error = caught(() => validator.validate(schema, {}));

    // Assert
    error.issues.length.should.equal(2);
    error.message.should.startWith('configuration validation failed on the final merged layer: port: ');
    error.message.should.containEql('; host: ');
  });
});
