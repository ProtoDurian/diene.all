import type { AppliedMigration, ForkMarker, Migration, SqlRow } from './structures';

export interface ISqlExecutor {
  query<R extends SqlRow = SqlRow>(text: string, params?: readonly unknown[]): Promise<readonly R[]>;
}

export interface IDatabase {
  withTenant<T>(tenantId: string, work: (sql: ISqlExecutor) => Promise<T>): Promise<T>;
  withSystem<T>(work: (sql: ISqlExecutor) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

export interface IMigrationSource {
  list(): Promise<readonly Migration[]>;
}

export interface IMigrationSession {
  applied(): Promise<readonly AppliedMigration[]>;
  apply(migration: Migration): Promise<void>;
}

export interface IMigrationLedger {
  exclusive<T>(work: (session: IMigrationSession) => Promise<T>): Promise<T>;
}

export interface IForkMarkerReader {
  read(): Promise<ForkMarker>;
}
