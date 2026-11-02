import { describe, it } from 'bun:test';
import should from 'should';
import { NamespacedKeyValidationError, namespacedKey, slugify } from '../../src/lib/slug';

describe('slugify', () => {
  it.each([
    { input: 'Hello World', expected: 'hello-world' },
    { input: '  Trim Me  ', expected: 'trim-me' },
    { input: 'Multiple   Spaces', expected: 'multiple-spaces' },
    { input: 'Symbols!@#Here', expected: 'symbols-here' },
    { input: 'already-slugged', expected: 'already-slugged' },
    { input: 'mañana', expected: 'manana' },
    { input: 'résumé café', expected: 'resume-cafe' },
  ])('should slugify "$input" to "$expected"', ({ input, expected }) => {
    const actual = slugify(input);

    should(actual).equal(expected);
  });

  it('should collapse a fully non-alphanumeric string to empty', () => {
    const input = '!!! ???';
    const expected = '';

    const actual = slugify(input);

    should(actual).equal(expected);
  });
});

describe('namespacedKey', () => {
  it('should join a slugified namespace and key with a colon', () => {
    const namespace = 'Bun Base';
    const key = 'Sample Key';
    const expected = 'bun-base:sample-key';

    const actual = namespacedKey(namespace, key);

    should(actual).equal(expected);
  });

  it('should throw NamespacedKeyValidationError when the namespace slugifies to empty', () => {
    const namespace = '!!!';
    const key = 'key';

    const actual = () => namespacedKey(namespace, key);

    should(actual).throw(NamespacedKeyValidationError, { message: 'namespace must not be empty' });
  });

  it('should throw NamespacedKeyValidationError when the key slugifies to empty', () => {
    const namespace = 'ns';
    const key = '!!!';

    const actual = () => namespacedKey(namespace, key);

    should(actual).throw(NamespacedKeyValidationError, { message: 'key must not be empty' });
  });
});
