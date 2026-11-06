export type SqlRow = Record<string, unknown>;

export interface Migration {
  readonly version: number;
  readonly name: string;
  readonly sql: string;
  readonly checksum: string;
}

export interface AppliedMigration {
  readonly version: number;
  readonly name: string;
  readonly checksum: string;
}

export type MigrationDriftKind = 'duplicate' | 'missing' | 'changed' | 'out_of_order';

export interface MigrationDrift {
  readonly kind: MigrationDriftKind;
  readonly version: number;
  readonly name: string;
}

export interface ForkMarker {
  readonly isFork: boolean;
  readonly source?: string;
  readonly forkedAt?: Date;
}
