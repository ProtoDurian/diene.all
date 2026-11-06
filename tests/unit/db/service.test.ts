import { describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import type { IMigrationLedger, IMigrationSession, IMigrationSource } from '../../../src/lib/db/interfaces';
import { MigrationPlanner, MigrationService } from '../../../src/lib/db/service';
import type { AppliedMigration, Migration } from '../../../src/lib/db/structures';

const migration = (version: number, checksum = `sum-${version}`): Migration => ({
  version,
  name: `${String(version).padStart(4, '0')}_step`,
  sql: `SELECT ${version};`,
  checksum,
});

const applied = (entry: Migration): AppliedMigration => ({
  version: entry.version,
  name: entry.name,
  checksum: entry.checksum,
});

class MemorySource implements IMigrationSource {
  constructor(private readonly migrations: readonly Migration[]) {}

  async list(): Promise<readonly Migration[]> {
    return this.migrations;
  }
}

class MemoryLedger implements IMigrationLedger, IMigrationSession {
  readonly ran: string[] = [];
  locks = 0;

  constructor(private readonly done: AppliedMigration[] = []) {}

  async exclusive<T>(work: (session: IMigrationSession) => Promise<T>): Promise<T> {
    this.locks++;
    return work(this);
  }

  async applied(): Promise<readonly AppliedMigration[]> {
    return this.done;
  }

  async apply(entry: Migration): Promise<void> {
    this.ran.push(entry.name);
    this.done.push(applied(entry));
  }
}

describe('MigrationPlanner', () => {
  const subject = new MigrationPlanner();

  it('should return the unapplied migrations in version order', async () => {
    // Arrange
    const [one, two, three] = [migration(1), migration(2), migration(3)];

    // Act
    const actual = await expectOk(subject.plan([three, one, two], [applied(one)]));

    // Assert
    actual.map(entry => entry.version).should.deepEqual([2, 3]);
  });

  it.each([
    { kind: 'duplicate', available: [migration(1), migration(1, 'other')], done: [] },
    { kind: 'missing', available: [migration(1)], done: [applied(migration(2))] },
    { kind: 'changed', available: [migration(1, 'edited')], done: [applied(migration(1))] },
    { kind: 'out_of_order', available: [migration(1), migration(2), migration(3)], done: [applied(migration(1)), applied(migration(3))] },
  ])('should refuse $kind drift', async ({ kind, available, done }) => {
    // Act
    const actual = await expectErr(subject.plan(available, done));

    // Assert
    actual.kind.should.equal(kind);
  });
});

describe('MigrationPlanner allowing out-of-order files', () => {
  it('should plan a late lower version when told to', async () => {
    // Arrange
    const subject = new MigrationPlanner(true);

    // Act
    const actual = await expectOk(subject.plan([migration(1), migration(2), migration(3)], [applied(migration(1)), applied(migration(3))]));

    // Assert
    actual.map(entry => entry.version).should.deepEqual([2]);
  });
});

describe('MigrationService', () => {
  it('should apply every pending migration inside one exclusive session', async () => {
    // Arrange
    const ledger = new MemoryLedger([applied(migration(1))]);
    const subject = new MigrationService(
      new MemorySource([migration(1), migration(2), migration(3)]),
      ledger,
      new MigrationPlanner(),
    );

    // Act
    const actual = await expectOk(subject.migrate());

    // Assert
    actual.should.deepEqual(['0002_step', '0003_step']);
    ledger.ran.should.deepEqual(['0002_step', '0003_step']);
    ledger.locks.should.equal(1);
  });

  it('should apply nothing when the plan finds drift', async () => {
    // Arrange
    const ledger = new MemoryLedger([applied(migration(1, 'old'))]);
    const subject = new MigrationService(new MemorySource([migration(1), migration(2)]), ledger, new MigrationPlanner());

    // Act
    const actual = await expectErr(subject.migrate());

    // Assert
    actual.should.deepEqual({ kind: 'changed', version: 1, name: '0001_step' });
    ledger.ran.should.deepEqual([]);
  });
});
