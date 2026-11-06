import { describe, it } from 'bun:test';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import type { BucketForker, DatabaseBrancher, ForkSanitizer, SecretGenerator } from '../../../src/lib/fork/interfaces';
import { ForkNaming } from '../../../src/lib/fork/naming';
import { ForkService } from '../../../src/lib/fork/service';
import type { DatabaseBranch, ForkError, SanitizePlan, SanitizeReport } from '../../../src/lib/fork/structures';

const REPORT: SanitizeReport = { sessionsDeleted: 2, apiKeysDisabled: 1, jobsHeld: 3, secretRowsRotated: 4 };

function failure(step: 'database' | 'bucket' | 'sanitize'): ForkError {
  return { kind: 'provider_failed', step, message: `${step} broke` };
}

class MemoryDatabases implements DatabaseBrancher {
  readonly forks = new Set<string>();
  failCreate = false;
  failList = false;

  create(fork: string): Result<DatabaseBranch, ForkError> {
    if (this.failCreate) return Err(failure('database'));
    this.forks.add(fork);
    return Ok({ name: fork, connectionString: `postgres://db/${fork}` });
  }

  list(): Result<readonly string[], ForkError> {
    return this.failList ? Err(failure('database')) : Ok([...this.forks]);
  }

  delete(fork: string): Result<void, ForkError> {
    return this.forks.delete(fork) ? Ok(undefined) : Err({ kind: 'not_found', name: fork });
  }
}

class MemoryBuckets implements BucketForker {
  readonly forks = new Set<string>();
  failFork = false;
  failDelete = false;

  fork(fork: string): Result<string, ForkError> {
    if (this.failFork) return Err(failure('bucket'));
    this.forks.add(fork);
    return Ok(`files-fork-${fork}`);
  }

  list(): Result<readonly string[], ForkError> {
    return Ok([...this.forks]);
  }

  delete(fork: string): Result<void, ForkError> {
    if (this.failDelete) return Err(failure('bucket'));
    return this.forks.delete(fork) ? Ok(undefined) : Err({ kind: 'not_found', name: fork });
  }
}

class RecordingSanitizer implements ForkSanitizer {
  readonly calls: { branch: DatabaseBranch; plan: SanitizePlan }[] = [];
  fail = false;

  sanitize(branch: DatabaseBranch, plan: SanitizePlan): Result<SanitizeReport, ForkError> {
    this.calls.push({ branch, plan });
    return this.fail ? Err(failure('sanitize')) : Ok(REPORT);
  }
}

class FixedSecret implements SecretGenerator {
  generate(): string {
    return 'new-secret';
  }
}

function setup() {
  const databases = new MemoryDatabases();
  const buckets = new MemoryBuckets();
  const sanitizer = new RecordingSanitizer();
  const subject = new ForkService(
    databases,
    buckets,
    sanitizer,
    new FixedSecret(),
    new ForkNaming({ database: 'aseity', bucket: 'files' }),
  );
  return { databases, buckets, sanitizer, subject };
}

describe('ForkService.create', () => {
  it('should copy the database and bucket, then sanitize the copy', async () => {
    // Arrange
    const { databases, buckets, sanitizer, subject } = setup();

    // Act
    const actual = await expectOk(subject.create('demo'));

    // Assert
    actual.should.deepEqual({
      name: 'demo',
      database: { name: 'demo', connectionString: 'postgres://db/demo' },
      bucket: 'files-fork-demo',
      authSecret: 'new-secret',
      report: REPORT,
    });
    sanitizer.calls.should.deepEqual([
      { branch: { name: 'demo', connectionString: 'postgres://db/demo' }, plan: { source: 'aseity' } },
    ]);
    [...databases.forks].should.deepEqual(['demo']);
    [...buckets.forks].should.deepEqual(['demo']);
  });

  it('should refuse an invalid name before touching any provider', async () => {
    // Arrange
    const { databases, subject } = setup();

    // Act
    const actual = await expectErr(subject.create('Bad Name'));

    // Assert
    actual.kind.should.equal('invalid_name');
    databases.forks.size.should.equal(0);
  });

  it('should refuse a fork that already exists', async () => {
    // Arrange
    const { buckets, subject } = setup();
    buckets.forks.add('demo');

    // Act
    const actual = await expectErr(subject.create('demo'));

    // Assert
    actual.should.deepEqual({ kind: 'already_exists', name: 'demo' });
  });

  it('should report a database copy failure', async () => {
    // Arrange
    const { databases, subject } = setup();
    databases.failCreate = true;

    // Act
    const actual = await expectErr(subject.create('demo'));

    // Assert
    actual.should.deepEqual(failure('database'));
  });

  it('should remove the database copy when the bucket copy fails', async () => {
    // Arrange
    const { databases, buckets, sanitizer, subject } = setup();
    buckets.failFork = true;

    // Act
    const actual = await expectErr(subject.create('demo'));

    // Assert
    actual.should.deepEqual(failure('bucket'));
    databases.forks.size.should.equal(0);
    sanitizer.calls.length.should.equal(0);
  });

  it('should remove both copies when sanitizing fails', async () => {
    // Arrange
    const { databases, buckets, sanitizer, subject } = setup();
    sanitizer.fail = true;

    // Act
    const actual = await expectErr(subject.create('demo'));

    // Assert
    actual.should.deepEqual(failure('sanitize'));
    databases.forks.size.should.equal(0);
    buckets.forks.size.should.equal(0);
  });
});

describe('ForkService.list', () => {
  it('should merge database and bucket forks by name, sorted', async () => {
    // Arrange
    const { databases, buckets, subject } = setup();
    databases.forks.add('zeta');
    databases.forks.add('alpha');
    buckets.forks.add('alpha');
    buckets.forks.add('beta');

    // Act
    const actual = await expectOk(subject.list());

    // Assert
    actual.should.deepEqual([
      { name: 'alpha', hasDatabase: true, hasBucket: true },
      { name: 'beta', hasDatabase: false, hasBucket: true },
      { name: 'zeta', hasDatabase: true, hasBucket: false },
    ]);
  });

  it('should report a listing failure', async () => {
    // Arrange
    const { databases, subject } = setup();
    databases.failList = true;

    // Act
    const actual = await expectErr(subject.list());

    // Assert
    actual.should.deepEqual(failure('database'));
  });
});

describe('ForkService.delete', () => {
  it('should delete both copies of a fork', async () => {
    // Arrange
    const { databases, buckets, subject } = setup();
    await expectOk(subject.create('demo'));

    // Act
    const actual = await expectOk(subject.delete('demo'));

    // Assert
    actual.should.deepEqual({ name: 'demo', database: true, bucket: true });
    databases.forks.size.should.equal(0);
    buckets.forks.size.should.equal(0);
  });

  it('should delete whichever half of a fork remains', async () => {
    // Arrange
    const { databases, buckets, subject } = setup();
    databases.forks.add('only-db');
    buckets.forks.add('only-bucket');

    // Act
    const db = await expectOk(subject.delete('only-db'));
    const bucket = await expectOk(subject.delete('only-bucket'));

    // Assert
    db.should.deepEqual({ name: 'only-db', database: true, bucket: false });
    bucket.should.deepEqual({ name: 'only-bucket', database: false, bucket: true });
    databases.forks.size.should.equal(0);
    buckets.forks.size.should.equal(0);
  });

  it('should report a fork that does not exist', async () => {
    // Arrange
    const { subject } = setup();

    // Act
    const actual = await expectErr(subject.delete('ghost'));

    // Assert
    actual.should.deepEqual({ kind: 'not_found', name: 'ghost' });
  });

  it('should keep the database when the bucket delete fails', async () => {
    // Arrange
    const { databases, buckets, subject } = setup();
    await expectOk(subject.create('demo'));
    buckets.failDelete = true;

    // Act
    const actual = await expectErr(subject.delete('demo'));

    // Assert
    actual.should.deepEqual(failure('bucket'));
    [...databases.forks].should.deepEqual(['demo']);
  });

  it('should refuse an invalid name', async () => {
    // Arrange
    const { subject } = setup();

    // Act
    const actual = await expectErr(subject.delete('-'));

    // Assert
    actual.kind.should.equal('invalid_name');
  });
});
