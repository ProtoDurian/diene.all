import { describe, it } from 'bun:test';
import { type CreateDirectoryOptions, VfsPolicy } from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

const policy = new VfsPolicy();

describe('VfsPolicy.validatePath', () => {
  it.each([
    ['a nested path', '/a/b/c'],
    ['the root', '/'],
  ])('should accept a canonical absolute path (%s)', async (_label, path) => {
    // Act
    const actual = await expectOk(policy.validatePath(path, 'stat'));

    // Assert
    actual.should.eql(path);
  });

  it.each([
    ['non-string', 5 as unknown as string],
    ['empty', ''],
    ['NUL', '/a\0b'],
  ])('should reject a non-usable path (%s)', async (_label, path) => {
    // Act
    const error = await expectErr(policy.validatePath(path, 'stat'));

    // Assert
    error.port.should.eql('vfs');
    error.details.should.eql({ field: 'path' });
    error.message.should.match(/non-empty NUL-free/);
  });

  it('should reject a relative path', async () => {
    // Act
    const error = await expectErr(policy.validatePath('a/b', 'stat'));

    // Assert
    error.message.should.match(/must be absolute/);
  });

  it.each([
    ['trailing slash', '/a/'],
    ['double slash', '/a//b'],
  ])('should reject a non-canonical path (%s)', async (_label, path) => {
    // Act
    const error = await expectErr(policy.validatePath(path, 'stat'));

    // Assert
    error.message.should.match(/must be canonical/);
  });

  it.each([
    ['single dot', '/a/./b'],
    ['double dot', '/a/../b'],
  ])('should reject dot segments (%s)', async (_label, path) => {
    // Act
    const error = await expectErr(policy.validatePath(path, 'stat'));

    // Assert
    error.message.should.match(/must not contain dot segments/);
  });

  it('should carry the supplied operation label', async () => {
    // Act
    const error = await expectErr(policy.validatePath('bad', 'readFile'));

    // Assert
    error.operation.should.eql('readFile');
  });
});

describe('VfsPolicy.validateContents', () => {
  it('should accept and defensively copy Uint8Array bytes', async () => {
    // Arrange
    const source = new Uint8Array([1, 2, 3]);

    // Act
    const actual = await expectOk(policy.validateContents(source));
    source[0] = 9;

    // Assert
    (actual === source).should.be.false();
    Array.from(actual).should.eql([1, 2, 3]);
  });

  it('should reject non-Uint8Array contents', async () => {
    // Act
    const error = await expectErr(policy.validateContents([1, 2, 3] as unknown as Uint8Array));

    // Assert
    error.port.should.eql('vfs');
    error.operation.should.eql('writeFile');
    error.details.should.eql({ field: 'contents' });
  });
});

describe('recursive option validators', () => {
  it.each([
    ['create', (options: CreateDirectoryOptions | undefined) => policy.validateCreateDirectoryOptions(options)],
    ['remove', (options: CreateDirectoryOptions | undefined) => policy.validateRemoveOptions(options)],
  ])('should default undefined options to non-recursive (%s)', async (_label, validate) => {
    // Act
    const actual = await expectOk(validate(undefined));

    // Assert
    actual.should.eql({ recursive: false });
    Object.isFrozen(actual).should.be.true();
  });

  it.each([
    ['explicit true', { recursive: true }, true],
    ['explicit false', { recursive: false }, false],
    ['empty object', {}, false],
  ])('should normalize a provided recursive flag (%s)', async (_label, options, expected) => {
    // Act
    const actual = await expectOk(policy.validateCreateDirectoryOptions(options));

    // Assert
    actual.should.eql({ recursive: expected });
  });

  it.each([
    ['null', null as unknown as CreateDirectoryOptions],
    ['an array', [] as unknown as CreateDirectoryOptions],
    ['a primitive', 3 as unknown as CreateDirectoryOptions],
    ['a class instance', new (class Opt {})() as unknown as CreateDirectoryOptions],
  ])('should reject a non-record options object (%s)', async (_label, options) => {
    // Act
    const error = await expectErr(policy.validateRemoveOptions(options));

    // Assert
    error.port.should.eql('vfs');
    error.operation.should.eql('remove');
    error.details.should.eql({ field: 'options' });
  });

  it('should reject a non-boolean recursive flag with the operation label', async () => {
    // Act
    const error = await expectErr(policy.validateCreateDirectoryOptions({ recursive: 'yes' as unknown as boolean }));

    // Assert
    error.operation.should.eql('createDirectory');
    error.details.should.eql({ field: 'recursive' });
  });
});

describe('VfsPolicy.checkPath', () => {
  it('should expose accepted and rejected Checked branches', () => {
    // Act
    const ok = policy.checkPath('/a', 'list');
    const bad = policy.checkPath('relative', 'list');

    // Assert
    ok.ok.should.be.true();
    if (ok.ok) ok.value.should.eql('/a');
    bad.ok.should.be.false();
    if (!bad.ok) bad.error.operation.should.eql('list');
  });
});

describe('VfsPolicy.validateRecursiveOptions', () => {
  it.each([
    ['createDirectory', 'createDirectory' as const],
    ['remove', 'remove' as const],
  ])('should label a rejection with the given operation (%s)', async (_label, operation) => {
    // Act
    const error = await expectErr(
      policy.validateRecursiveOptions(null as unknown as CreateDirectoryOptions, operation),
    );

    // Assert
    error.operation.should.eql(operation);
    error.details.should.eql({ field: 'options' });
  });

  it('should normalize accepted options', async () => {
    // Act
    const actual = await expectOk(policy.validateRecursiveOptions({ recursive: true }, 'remove'));

    // Assert
    actual.should.eql({ recursive: true });
  });
});
