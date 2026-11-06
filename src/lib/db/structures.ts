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

export interface MigrationDrift {
  readonly kind: 'duplicate' | 'missing' | 'changed' | 'out_of_order';
  readonly version: number;
  readonly name: string;
}

export interface ForkMarker {
  readonly isFork: boolean;
  readonly source?: string;
  readonly forkedAt?: Date;
}
