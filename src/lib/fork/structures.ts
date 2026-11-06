export interface DatabaseBranch {
  readonly name: string;
  readonly connectionString: string;
}

export interface SanitizeReport {
  readonly sessionsDeleted: number;
  readonly apiKeysDisabled: number;
  readonly jobsHeld: number;
  readonly secretRowsRotated: number;
}

export interface SanitizePlan {
  readonly source: string;
}

export interface ForkCreated {
  readonly name: string;
  readonly database: DatabaseBranch;
  readonly bucket: string;
  readonly authSecret: string;
  readonly report: SanitizeReport;
}

export interface ForkSummary {
  readonly name: string;
  readonly hasDatabase: boolean;
  readonly hasBucket: boolean;
}

export interface ForkDeleted {
  readonly name: string;
  readonly database: boolean;
  readonly bucket: boolean;
}

export type ForkStep = 'database' | 'bucket' | 'sanitize';

export type ForkError =
  | { readonly kind: 'invalid_name'; readonly name: string; readonly reason: string }
  | { readonly kind: 'already_exists'; readonly name: string }
  | { readonly kind: 'not_found'; readonly name: string }
  | { readonly kind: 'provider_failed'; readonly step: ForkStep; readonly message: string };

export interface ForkSources {
  readonly database: string;
  readonly bucket: string;
}
