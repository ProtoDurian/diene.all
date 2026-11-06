import { describe, it } from 'bun:test';
import 'should';
import { NamespacedKeyValidationError, Slugger } from '../../src/lib/slug';
import { expectErr, expectOk } from './support/result';

describe('Slugger.slugify', () => {
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
    const slugger = new Slugger();

    // Act
    const actual = slugger.slugify(input);

    // Assert
    actual.should.equal(expected);
  });
});

describe('Slugger.namespacedKey', () => {
  it('should return an Ok holding the composed key', async () => {
    // Arrange
    const slugger = new Slugger();

    // Act
    const actual = slugger.namespacedKey('Bun Core Utils', 'Published Result');

    // Assert
    (await expectOk(actual)).should.equal('bun-core-utils:published-result');
    (await actual.serial()).should.deepEqual(['ok', 'bun-core-utils:published-result']);
  });

  it.each([
    { namespace: '!!!', key: 'key', field: 'namespace', message: 'namespace must not be empty' },
    { namespace: 'namespace', key: '!!!', field: 'key', message: 'key must not be empty' },
  ])('should return an Err when $field slugifies to empty', async ({ namespace, key, field, message }) => {
    // Arrange
    const slugger = new Slugger();

    // Act
    const actual = await expectErr(slugger.namespacedKey(namespace, key));

    // Assert
    actual.should.be.instanceof(NamespacedKeyValidationError);
    actual.field.should.equal(field);
    actual.reason.should.equal('must not be empty');
    actual.message.should.equal(message);
    actual.name.should.equal('NamespacedKeyValidationError');
  });
});
