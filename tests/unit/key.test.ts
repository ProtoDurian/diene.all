import { describe, it } from 'bun:test';
import 'should';
import { KeyComposer, NamespacedKeyValidationError } from '../../src/lib/sample/key';

describe('KeyComposer.slugify', () => {
  it.each([
    { input: 'Hello World', expected: 'hello-world' },
    { input: '  Trim Me  ', expected: 'trim-me' },
    { input: 'Multiple   Spaces', expected: 'multiple-spaces' },
    { input: 'Symbols!@#Here', expected: 'symbols-here' },
    { input: 'already-slugged', expected: 'already-slugged' },
    { input: 'mañana', expected: 'manana' },
    { input: 'résumé café', expected: 'resume-cafe' },
    { input: '!!! ???', expected: '' },
  ])('should slugify "$input" to "$expected"', ({ input, expected }) => {
    // Arrange
    const subject = new KeyComposer('ns');

    // Act
    const actual = subject.slugify(input);

    // Assert
    actual.should.equal(expected);
  });
});

describe('KeyComposer.compose', () => {
  it('should join the slugified namespace and key with a colon', () => {
    // Arrange
    const subject = new KeyComposer('Bun Base');
    const expected = 'bun-base:sample-key';

    // Act
    const actual = subject.compose('Sample Key');

    // Assert
    actual.should.equal(expected);
  });

  it.each([
    { field: 'namespace', namespace: '!!!', key: 'key' },
    { field: 'key', namespace: 'ns', key: '!!!' },
  ])('should throw NamespacedKeyValidationError when the $field slugifies to empty', ({ field, namespace, key }) => {
    // Arrange
    const subject = new KeyComposer(namespace);

    // Act
    const act = () => subject.compose(key);

    // Assert
    act.should.throw(NamespacedKeyValidationError, { message: `${field} must not be empty` });
  });
});
