import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import type { IMigrationLedger, IMigrationSource } from './interfaces';
import type { AppliedMigration, Migration, MigrationDrift } from './structures';

export class MigrationPlanner {
  constructor(private readonly allowOutOfOrder = false) {}

  plan(
    available: readonly Migration[],
    applied: readonly AppliedMigration[],
  ): Result<readonly Migration[], MigrationDrift> {
    const byVersion = new Map<number, Migration>();
    for (const migration of available) {
      if (byVersion.has(migration.version)) return Err(this.drift('duplicate', migration));
      byVersion.set(migration.version, migration);
    }

    const appliedVersions = new Set<number>();
    let highestApplied = 0;
    for (const done of applied) {
      const known = byVersion.get(done.version);
      if (known === undefined) return Err(this.drift('missing', done));
      if (known.checksum !== done.checksum) return Err(this.drift('changed', done));
      appliedVersions.add(done.version);
      highestApplied = Math.max(highestApplied, done.version);
    }

    const pending = [...byVersion.values()]
      .filter(migration => !appliedVersions.has(migration.version))
      .sort((left, right) => left.version - right.version);
    const early = pending.find(migration => migration.version < highestApplied);
    if (early !== undefined && !this.allowOutOfOrder) return Err(this.drift('out_of_order', early));
    return Ok(pending);
  }

  private drift(kind: MigrationDrift['kind'], migration: AppliedMigration): MigrationDrift {
    return { kind, version: migration.version, name: migration.name };
  }
}

export class MigrationService {
  constructor(
    private readonly source: IMigrationSource,
    private readonly ledger: IMigrationLedger,
    private readonly planner: MigrationPlanner,
  ) {}

  migrate(): Result<readonly string[], MigrationDrift> {
    return Res.fromSerial(
      this.source.list().then(available =>
        this.ledger.exclusive(async session =>
          this.planner
            .plan(available, await session.applied())
            .andThen(async pending => {
              for (const migration of pending) await session.apply(migration);
              return Ok<readonly string[], MigrationDrift>(pending.map(migration => migration.name));
            })
            .serial(),
        ),
      ),
    );
  }
}
