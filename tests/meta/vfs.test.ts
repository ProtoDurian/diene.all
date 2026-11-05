import { describe, it } from 'bun:test';
import { portError, type VfsError } from '@atomicloud/diene.interfaces';
import { InMemoryVirtualFileSystem } from '@atomicloud/diene.interfaces/test-helper';
import type { Result } from '@atomicloud/diene.result';
import 'should';
import { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract } from './contract/behaviours.js';
import { expectErr, expectOk } from './support/capture.js';

const bytes = (...values: number[]): Uint8Array => new Uint8Array(values);
const vfs = (): InMemoryVirtualFileSystem => new InMemoryVirtualFileSystem();
const ioError = (operation: string): VfsError => portError('vfs', 'io', operation, 'disk fault');

describe('InMemoryVirtualFileSystem readFile', () => {
  it('should reject an invalid path', async () => {
    // Act
    const error = await expectErr(vfs().readFile('relative'));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should read back written bytes as an independent copy', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1, 2, 3)));

    // Act
    const read = await expectOk(subject.readFile('/f'));
    read[0] = 9;

    // Assert
    Array.from(await expectOk(subject.readFile('/f'))).should.eql([1, 2, 3]);
  });

  it('should surface not-found for a missing file', async () => {
    // Act
    const error = await expectErr(vfs().readFile('/missing'));

    // Assert
    error.code.should.eql('not-found');
  });

  it('should surface not-a-file for a directory', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));

    // Act
    const error = await expectErr(subject.readFile('/d'));

    // Assert
    error.code.should.eql('not-a-file');
  });

  it('should surface an injected failure before touching the node', async () => {
    // Arrange
    const subject = vfs();
    subject.failNext(ioError('readFile'));

    // Act
    const error = await expectErr(subject.readFile('/whatever'));

    // Assert
    error.code.should.eql('io');
  });
});

describe('InMemoryVirtualFileSystem writeFile', () => {
  it('should reject an invalid path', async () => {
    // Act
    const error = await expectErr(vfs().writeFile('bad', bytes(1)));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should reject non-Uint8Array contents', async () => {
    // Act
    const error = await expectErr(vfs().writeFile('/f', [1] as unknown as Uint8Array));

    // Assert
    error.details.should.eql({ field: 'contents' });
  });

  it('should surface an injected failure', async () => {
    // Arrange
    const subject = vfs();
    subject.failNext(ioError('writeFile'));

    // Act
    const error = await expectErr(subject.writeFile('/f', bytes(1)));

    // Assert
    error.code.should.eql('io');
  });

  it('should refuse to overwrite a directory with a file', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));

    // Act
    const error = await expectErr(subject.writeFile('/d', bytes(1)));

    // Assert
    error.code.should.eql('not-a-file');
  });

  it('should require an existing parent directory', async () => {
    // Act
    const error = await expectErr(vfs().writeFile('/missing/f', bytes(1)));

    // Assert
    error.code.should.eql('not-found');
  });

  it('should store a frozen defensive copy detached from the caller', async () => {
    // Arrange
    const subject = vfs();
    const source = bytes(1, 2);

    // Act
    await expectOk(subject.writeFile('/f', source));
    source[0] = 9;

    // Assert
    Array.from(await expectOk(subject.readFile('/f'))).should.eql([1, 2]);
  });
});

describe('InMemoryVirtualFileSystem under a file ancestor', () => {
  const underFile = (): InMemoryVirtualFileSystem => {
    const subject = vfs();
    subject.writeFile('/f', bytes(1));
    return subject;
  };

  it.each<[string, (subject: InMemoryVirtualFileSystem) => Result<unknown, VfsError>]>([
    ['readFile', subject => subject.readFile('/f/x')],
    ['writeFile', subject => subject.writeFile('/f/x', bytes(1))],
    ['stat', subject => subject.stat('/f/x/y')],
    ['list', subject => subject.list('/f/x')],
    ['createDirectory', subject => subject.createDirectory('/f/x')],
    ['remove', subject => subject.remove('/f/x', { recursive: true })],
  ])('should surface not-a-directory from %s', async (operation, call) => {
    // Arrange
    const subject = underFile();

    // Act
    const error = await expectErr(call(subject));

    // Assert
    error.code.should.eql('not-a-directory');
    error.operation.should.eql(operation);
    error.details.should.eql({ ancestor: '/f' });
  });

  it('should report absence from exists rather than fail', async () => {
    // Arrange
    const subject = underFile();

    // Act
    const actual = await expectOk(subject.exists('/f/x'));

    // Assert
    actual.should.be.false();
  });

  it('should leave no partial directories when a recursive create fails', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.createDirectory('/a'));
    await expectOk(subject.writeFile('/a/f', bytes(1)));

    // Act
    const error = await expectErr(subject.createDirectory('/a/f/x/y', { recursive: true }));

    // Assert
    error.code.should.eql('not-a-directory');
    (await expectOk(subject.list('/a'))).should.eql([{ kind: 'file', name: 'f' }]);
  });
});

describe('InMemoryVirtualFileSystem exists', () => {
  it('should reject an invalid path', async () => {
    // Act
    const error = await expectErr(vfs().exists('bad'));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should report presence and absence', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));

    // Act
    const present = await expectOk(subject.exists('/f'));
    const absent = await expectOk(subject.exists('/nope'));

    // Assert
    present.should.be.true();
    absent.should.be.false();
  });

  it('should surface an injected failure', async () => {
    // Arrange
    const subject = vfs();
    subject.failNext(ioError('exists'));

    // Act
    const error = await expectErr(subject.exists('/f'));

    // Assert
    error.code.should.eql('io');
  });
});

describe('InMemoryVirtualFileSystem stat', () => {
  it('should reject an invalid path', async () => {
    // Act
    const error = await expectErr(vfs().stat('bad'));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should surface an injected failure', async () => {
    // Arrange
    const subject = vfs();
    subject.failNext(ioError('stat'));

    // Act
    const code = await expectErr(subject.stat('/')).then(e => e.code);

    // Assert
    code.should.eql('io');
  });

  it('should surface not-found for a missing path', async () => {
    // Act
    const error = await expectErr(vfs().stat('/missing'));

    // Assert
    error.code.should.eql('not-found');
  });

  it('should report file size and zero-size directories', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1, 2, 3, 4)));

    // Act
    const file = await expectOk(subject.stat('/f'));
    const root = await expectOk(subject.stat('/'));

    // Assert
    file.should.eql({ kind: 'file', size: 4 });
    root.should.eql({ kind: 'directory', size: 0 });
  });
});

describe('InMemoryVirtualFileSystem list', () => {
  it('should reject an invalid path', async () => {
    // Act
    const error = await expectErr(vfs().list('bad'));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should surface an injected failure', async () => {
    // Arrange
    const subject = vfs();
    subject.failNext(ioError('list'));

    // Act
    const error = await expectErr(subject.list('/'));

    // Assert
    error.code.should.eql('io');
  });

  it('should surface not-found for a missing directory', async () => {
    // Act
    const error = await expectErr(vfs().list('/missing'));

    // Assert
    error.code.should.eql('not-found');
  });

  it('should surface not-a-directory for a file', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));

    // Act
    const error = await expectErr(subject.list('/f'));

    // Assert
    error.code.should.eql('not-a-directory');
  });

  it('should list only direct children, sorted, excluding deeper descendants', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.createDirectory('/a'));
    await expectOk(subject.createDirectory('/a/sub'));
    await expectOk(subject.writeFile('/a/file', bytes(1)));
    await expectOk(subject.writeFile('/a/sub/deep', bytes(1)));

    // Act
    const entries = await expectOk(subject.list('/a'));

    // Assert
    entries.should.eql([
      { kind: 'file', name: 'file' },
      { kind: 'directory', name: 'sub' },
    ]);
  });

  it('should list children of the root using the root prefix', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/top', bytes(1)));

    // Act
    const entries = await expectOk(subject.list('/'));

    // Assert
    entries.should.eql([{ kind: 'file', name: 'top' }]);
  });

  it('should sort many children written in reverse order', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/zed', bytes(1)));
    await expectOk(subject.writeFile('/mid', bytes(1)));
    await expectOk(subject.writeFile('/abc', bytes(1)));

    // Act
    const entries = await expectOk(subject.list('/'));

    // Assert
    entries.map(entry => entry.name).should.eql(['abc', 'mid', 'zed']);
  });
});

describe('InMemoryVirtualFileSystem createDirectory', () => {
  it('should reject an invalid path', async () => {
    // Act
    const error = await expectErr(vfs().createDirectory('bad'));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should reject a non-boolean recursive option', async () => {
    // Act
    const error = await expectErr(vfs().createDirectory('/d', { recursive: 'x' as unknown as boolean }));

    // Assert
    error.details.should.eql({ field: 'recursive' });
  });

  it('should surface an injected failure', async () => {
    // Arrange
    const subject = vfs();
    subject.failNext(ioError('createDirectory'));

    // Act
    const error = await expectErr(subject.createDirectory('/d'));

    // Assert
    error.code.should.eql('io');
  });

  it.each([
    ['non-recursive', false],
    ['recursive', true],
  ])('should surface already-exists where a file exists (%s)', async (_label, recursive) => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));

    // Act
    const error = await expectErr(subject.createDirectory('/f', { recursive }));

    // Assert
    error.code.should.eql('already-exists');
    (await expectOk(subject.stat('/f'))).kind.should.eql('file');
  });

  it('should be idempotent on an existing directory only when recursive', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));

    // Act
    await expectOk(subject.createDirectory('/d', { recursive: true }));
    const error = await expectErr(subject.createDirectory('/d'));

    // Assert
    error.code.should.eql('already-exists');
  });

  it('should create ancestors recursively but stop at a file ancestor', async () => {
    // Arrange
    const subject = vfs();

    // Act
    await expectOk(subject.createDirectory('/a/b/c', { recursive: true }));
    const ancestor = await expectOk(subject.stat('/a/b'));
    await expectOk(subject.writeFile('/file', bytes(1)));
    const error = await expectErr(subject.createDirectory('/file/x', { recursive: true }));

    // Assert
    ancestor.kind.should.eql('directory');
    error.code.should.eql('not-a-directory');
  });

  it('should require an existing parent when non-recursive', async () => {
    // Act
    const error = await expectErr(vfs().createDirectory('/x/y'));

    // Assert
    error.code.should.eql('not-found');
  });

  it('should create a directory under an existing parent', async () => {
    // Arrange
    const subject = vfs();

    // Act
    await expectOk(subject.createDirectory('/z'));

    // Assert
    (await expectOk(subject.stat('/z'))).kind.should.eql('directory');
  });
});

describe('InMemoryVirtualFileSystem remove', () => {
  it('should reject an invalid path', async () => {
    // Act
    const error = await expectErr(vfs().remove('bad'));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should reject a non-boolean recursive option', async () => {
    // Act
    const error = await expectErr(vfs().remove('/d', { recursive: 'x' as unknown as boolean }));

    // Assert
    error.details.should.eql({ field: 'recursive' });
  });

  it('should surface an injected failure', async () => {
    // Arrange
    const subject = vfs();
    subject.failNext(ioError('remove'));

    // Act
    const error = await expectErr(subject.remove('/d'));

    // Assert
    error.code.should.eql('io');
  });

  it('should refuse to remove the root', async () => {
    // Act
    const error = await expectErr(vfs().remove('/'));

    // Assert
    error.code.should.eql('unsupported');
  });

  it('should surface not-found for a missing path', async () => {
    // Act
    const error = await expectErr(vfs().remove('/missing'));

    // Assert
    error.code.should.eql('not-found');
  });

  it('should refuse to remove a non-empty directory without recursive', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));
    await expectOk(subject.writeFile('/d/f', bytes(1)));

    // Act
    const error = await expectErr(subject.remove('/d'));

    // Assert
    error.code.should.eql('directory-not-empty');
  });

  it('should remove a directory tree recursively', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));
    await expectOk(subject.writeFile('/d/f', bytes(1)));

    // Act
    await expectOk(subject.remove('/d', { recursive: true }));

    // Assert
    (await expectOk(subject.exists('/d'))).should.be.false();
    (await expectOk(subject.exists('/d/f'))).should.be.false();
  });

  it('should remove a file and an empty directory', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));

    // Act
    await expectOk(subject.remove('/f'));
    await expectOk(subject.createDirectory('/e'));
    await expectOk(subject.remove('/e'));

    // Assert
    (await expectOk(subject.exists('/f'))).should.be.false();
    (await expectOk(subject.exists('/e'))).should.be.false();
  });
});

describe('InMemoryVirtualFileSystem recorded state', () => {
  it('should clone writeFile contents in the calls getter', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1, 2)));
    await expectOk(subject.exists('/f'));

    // Act
    const calls = subject.calls;
    const writeCall = calls[0];
    if (writeCall?.method !== 'writeFile') throw new Error('expected writeFile call');
    writeCall.contents[0] = 9;

    // Assert
    const reread = subject.calls[0];
    if (reread?.method !== 'writeFile') throw new Error('expected writeFile call');
    Array.from(reread.contents).should.eql([1, 2]);
    calls[1]?.method.should.eql('exists');
  });

  it('should expose files in code-unit order with independent byte copies', async () => {
    // Arrange
    // Locale order (a, B, Z) must differ from code-unit order (B, Z, a).
    const subject = vfs();
    await expectOk(subject.writeFile('/a', bytes(1)));
    await expectOk(subject.writeFile('/Z', bytes(2)));
    await expectOk(subject.writeFile('/B', bytes(3)));

    // Act
    const files = subject.files;
    (files['/a'] as Uint8Array)[0] = 9;

    // Assert
    Object.keys(files).should.eql(['/B', '/Z', '/a']);
    Array.from(subject.files['/a'] as Uint8Array).should.eql([1]);
  });

  it('should satisfy the sequence contract across mixed calls', async () => {
    // Arrange
    const subject = vfs();

    // Assert
    await runSequenceContract({
      label: 'InMemoryVirtualFileSystem',
      record: async () => {
        await subject.exists('/probe');
      },
      sequences: () => subject.calls.map(call => call.sequence),
    });
  });

  it('should satisfy the one-shot fault-injection contract', async () => {
    // Arrange
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));

    // Assert
    await runFailInjectionContract({
      label: 'InMemoryVirtualFileSystem',
      makeError: () => ioError('exists'),
      injectFailure: error => subject.failNext(error),
      callFallible: () => subject.exists('/f'),
    });
  });

  it('should satisfy the snapshot isolation contract', async () => {
    // Arrange
    const subject = vfs();

    // Assert
    await runSnapshotIsolationContract({
      label: 'InMemoryVirtualFileSystem',
      produce: async () => {
        await subject.exists('/probe');
      },
      readSnapshot: () => subject.calls,
    });
  });
});
