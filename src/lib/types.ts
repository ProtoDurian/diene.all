import type { z } from 'zod';

export type JsonSchema = Readonly<Record<string, unknown>>;

export interface ErrorPortalConfig {
  readonly scheme: 'http' | 'https';
  readonly host: string;
  readonly landscape: string;
  readonly platform: string;
  readonly service: string;
  readonly module: string;
}

export type ProblemDataSchema = z.ZodType | undefined;

export type ProblemDataOf<TSchema extends ProblemDataSchema> = TSchema extends z.ZodType
  ? z.output<TSchema>
  : undefined;

export type ProblemDataInputOf<TSchema extends ProblemDataSchema> = TSchema extends z.ZodType
  ? z.input<TSchema>
  : undefined;

export interface ProblemDefinition<TSchema extends ProblemDataSchema = ProblemDataSchema> {
  readonly id: string;
  readonly title: string;
  readonly status: number;
  readonly recoverable: boolean;
  readonly version: string;
  readonly dataSchema?: TSchema;
}

export interface RegisteredProblem<TSchema extends ProblemDataSchema = ProblemDataSchema>
  extends ProblemDefinition<TSchema> {
  readonly type: string;
  readonly schema: JsonSchema;
}

export type ProblemData<TDefinition extends ProblemDefinition> =
  TDefinition extends ProblemDefinition<infer TSchema> ? ProblemDataOf<TSchema> : never;

export type ProblemDataMember<TData> = unknown extends TData
  ? { readonly data?: unknown }
  : [TData] extends [undefined]
    ? { readonly data?: undefined }
    : undefined extends TData
      ? { readonly data?: TData }
      : { readonly data: TData };

interface ProblemEnvelope {
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly detail?: string;
  readonly instance?: string;
}

export type Problem<TData = unknown> = ProblemEnvelope & ProblemDataMember<TData>;

export type ProblemDetail<TData = unknown> = Problem<TData>;

export type ProblemInit<TData = unknown> = {
  readonly detail?: string;
  readonly instance?: string;
  readonly status?: number;
} & ProblemDataMember<TData>;

export interface ProblemEndpoint {
  readonly method: string;
  readonly path: string;
}

export interface ProblemManifestEntry {
  readonly id: string;
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly recoverable: boolean;
  readonly version: string;
  readonly data: JsonSchema;
}

export interface ProblemManifest {
  readonly problems: readonly ProblemManifestEntry[];
  readonly schemas: Readonly<Record<string, JsonSchema>>;
}

export interface ProblemCatalogEntry {
  readonly id: string;
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly recoverable: boolean;
  readonly version: string;
  readonly data: JsonSchema;
  readonly endpoints: readonly ProblemEndpoint[];
}

export interface ProblemCatalogDeclaration {
  readonly endpoints: readonly ProblemEndpoint[];
}

export interface ProblemResourceIdentity {
  readonly platform: string;
  readonly service: string;
  readonly module: string;
  readonly landscape: string;
  readonly version: string;
}

export interface ProblemResourceEntry {
  readonly id: string;
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly recoverable: boolean;
  readonly schema: JsonSchema;
  readonly endpoints: readonly ProblemEndpoint[];
}

export interface ProblemResource {
  readonly apiVersion: 'atomi.cloud/v1alpha1';
  readonly kind: 'Problem';
  readonly metadata: {
    readonly name: string;
    readonly namespace: string;
  };
  readonly spec: ProblemResourceIdentity & {
    readonly problems: readonly ProblemResourceEntry[];
  };
}
