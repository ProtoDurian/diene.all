export interface RedisEnvironment {
  readonly [name: string]: string | undefined;
}

export interface RedisConnection {
  readonly host: string;
  readonly port: number;
}

export type RedisConfigResult =
  | { readonly ok: true; readonly connection: RedisConnection | undefined }
  | { readonly ok: false; readonly issues: readonly string[] };
