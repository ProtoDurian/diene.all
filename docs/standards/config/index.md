# Configuration

`@atomicloud/diene.config` is the one config-loading engine for the AtomiCloud
TypeScript family (the R14 config contract). It loads YAML layers, deep-merges
them, validates the service-composed root schema, and serves typed slices via
`config(key)`. It is the family's only merger/validator: engine libraries
(auth-engine, otel, api-engine, …) each own and export their own zod block
schema next to the code that reads it — this lib never defines engine block
schemas, it only merges and validates against whatever root schema a service
composes.

Config is immutable per process — there is no watch/reload in v1. Dev iteration
relies on the framework's HMR/restart.

## The 4-tier merge

Layers apply in strict order, each overriding the previous:

1. **base YAML** — the full defaults (`config/config.yaml`), first line
   `# yaml-language-server: $schema=./schema.json`.
2. **sparse landscape overlay** — only the keys that differ for a landscape
   (`config/<landscape>.config.yaml`).
3. **build-time injection** — values frozen into a bundle at build.
4. **runtime env** — applied LAST; wins over every file tier.

Validation is fail-fast at startup and runs on the **final merged layer only** —
intermediate tiers are never validated. A base file may be individually
incomplete as long as the merged result satisfies the root schema.

## Env-override contract

- **`prefix` is REQUIRED and configurable** — there is no baked default in the
  lib. The app/template sets it (for example `ATOMI_`).
- **`__` is the nesting separator.** `ATOMI_SERVER__PORT` targets
  `server.port`.
- **Case- and separator-insensitive key matching.** A snake segment matches
  snake / Pascal / camel / kebab object keys: `SERVER__MAX_RETRIES` matches
  `maxRetries`.
- **Lists use indexed keys** — `FOO__0`, `FOO__1`, … There is NO JSON-in-env and
  NO comma encoding; this is specced family-wide (in YAML too).
- **Number/boolean coercion goes through zod, never a hand-rolled `Number()`**
  (M31). Declare env-overridable numeric fields with `z.coerce.number()`.
- **A blank env value means UNSET** (M33): it is dropped, leaving the file value,
  never written as an empty string.
- **Secrets are blank in YAML** and injected at runtime (Infisical). Since
  secrets only materialize as runtime env, a fully-static frontend carries none.

## Landscape resolution

The host supplies the landscape; this lib never detects it (it does not import
frontend-utils). `LandscapeResolver.resolve` prefers an explicit landscape, then
the service-tree `app.landscape` field in the base config, then `base` (defaults
only). Landscape names must be a lowercase token (`[a-z0-9][a-z0-9-]*`).

## The dimension matrix and `/build-time`

Build-time is a dimension for ALL app types: shared / client / server crossed
with build-time / runtime.

| Config class                    | Where it lives                                    | Ends up in the bundle |
| ------------------------------- | ------------------------------------------------- | --------------------- |
| runtime value or runtime secret | runtime `ConfigLoader` (package root), SSR/server | no                    |
| build-time client value         | `/build-time` `BuildTimeValueMapper`              | yes                   |
| build-time secret               | CI env read by the build step only                | never                 |

- The **runtime loader** keeps SSR/server-side runtime secrets.
- **`BuildTimeValueMapper.map(env, prefix)`** (`/build-time`) returns the
  prefixed, non-blank variables to inline with a DefinePlugin-style static
  injection. nextjs owns the DefinePlugin wiring; this lib owns the value map.
  Runtime env still wins over a frozen build-time value.
- **Build-time secrets** (e.g. the Faro source-map upload key
  `ATOMI_CLIENT__FARO__BUILD__KEY`) are CI-injected during the build, consumed by
  the build step only, and NEVER persisted into the artifact.
- **No-runtime-env mode:** a fully-static frontend carries zero runtime env vars,
  so it carries no secrets at runtime.

## Public surface

Every piece is a stateless class; collaborators are constructor-injected with
working defaults.

| Class                                                     | Methods                                                                                   |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `ConfigRegistry`                                          | `create()`, `register(key, schema)`, `keys`, `rootSchema()`                               |
| `ConfigLoader(source, registry, options, collaborators?)` | `load()`, `loadResult()`                                                                  |
| `FrozenConfig` (implements `Config`)                      | `get(key)`, `all()`                                                                       |
| `YamlConfigSource(options)`                               | the real `ConfigSource`: `base()`, `overlay(landscape)`, `buildTimeEnv()`, `runtimeEnv()` |
| `DeepMerger`                                              | `merge(base, override)`                                                                   |
| `EnvOverrides(coercer?, matcher?)`                        | `apply(target, env, prefix)`                                                              |
| `EnvKeyMatcher`                                           | `normalize(key)`, `match(keys, segment)`                                                  |
| `ScalarCoercer`                                           | `coerce(raw)`                                                                             |
| `LandscapeResolver`                                       | `resolve(explicit, base)`                                                                 |
| `ConfigValidator`                                         | `validate(schema, value)`                                                                 |
| `JsonSchemaGenerator`                                     | `generate(registry, { id? })`                                                             |
| `BuildTimeValueMapper` (`/build-time`)                    | `map(env, prefix)`                                                                        |

- `load()` throws `ConfigValidationError` (aggregated, per-path issues) on an
  invalid final layer; `loadResult()` returns it as an `Err` instead, using
  `@atomicloud/diene.result`. IO failures throw from both.
- An empty `prefix` throws `ConfigLoaderError`.
- `JsonSchemaGenerator` emits the JSON Schema a config YAML's first line points
  at: `# yaml-language-server: $schema=./schema.json`.
- `DeepMerger`, `EnvOverrides` and the coercion classes live here; this lib is
  their only consumer-facing home (moved out of core-utils).

```ts
const registry = ConfigRegistry.create().register('server', ServerBlock);
const loader = new ConfigLoader(new YamlConfigSource({ dir: 'config' }), registry, { prefix: 'ATOMI_' });
const config = await loader.load();
const server = config.get('server');
```

## TestHelper (`/test-helper`)

`@atomicloud/diene.config/test-helper` fakes the IO a consumer would otherwise
rebuild:

- `InMemoryConfigSource(tiers)` — base / overlays / build-time / runtime tiers
  as plain objects; no files, no `process.env` mutation.
- `LandscapeConfigSource(landscape, tiers)` — the landscape fake: an in-memory
  source whose base carries `app.landscape`.
- `ConfigStubBuilder(registry, { prefix?, landscape? })` — `build(tiers)` runs
  the real loader, so a stub always passes the registry.
- `ConfigAssertions(builder)` — `expectValid(tiers)` / `expectInvalid(tiers)`;
  each throws `TestHelperError` when the expectation fails.

The fakes feed the same loader as production, so one behavioural suite proves
real-vs-fake parity. Helper-only dependencies are optional peerDependencies,
never regular dependencies. The meta tier measures coverage over TestHelper code
only.
