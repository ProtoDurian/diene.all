---
name: diene-config-usage
description: Use when consuming @atomicloud/diene.config — registering config blocks, running the 4-tier loader, the build-time (/build-time) variant, env-override rules, or faking config in tests via /test-helper.
---

# Diene Config usage

Import only the package root, `/build-time` or `/test-helper`; never copy the
implementation or reach into `src/` or `dist/`. Everything a consumer needs is in
this skill and its [assets](assets/test-helper.md); the full contract lives in
`docs/standards/config/index.md` of the library's source repository.

## Load configuration (runtime)

1. Each engine library exports its own zod block schema; the service composes
   them: `ConfigRegistry.create().register('server', ServerBlock)`.
2. Load through `new ConfigLoader(new YamlConfigSource({ dir: 'config' }), registry, { prefix: 'ATOMI_' })`.
   It merges base YAML → landscape overlay → build-time → runtime env (last) and
   validates the final layer only, fail-fast.
3. `await loader.load()` returns the typed `Config`: `config.get('server')`,
   `config.all()`. `loader.loadResult()` returns a `Result` instead of throwing
   on a validation failure.

Copyable examples: `assets/consumer.ts` (ESM), `assets/consumer.cjs` (CJS).

## Dimension matrix: `/build-time` vs the runtime loader

Build-time is a dimension for every app type: shared/client/server crossed with
build-time/runtime.

| Need                                             | Use                                                                                              |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Server/SSR config, runtime secrets               | runtime `ConfigLoader` (package root)                                                            |
| Client values inlined into a bundle              | `new BuildTimeValueMapper().map(env, prefix)` (`/build-time`), fed to the bundler's DefinePlugin |
| Build-time secret (e.g. a source-map upload key) | read by the build step only; never inlined or persisted                                          |
| Fully-static frontend                            | build-time values only; zero runtime env, so no runtime secrets                                  |

Runtime env still wins over a build-time value wherever both exist.
`BuildTimeValueMapper` keeps only `<prefix>CLIENT__*` and `<prefix>SHARED__*` keys and drops any key with a `BUILD` segment.
`shared.*` is inlined into client bundles: never put a secret there.

## Env-override rules

- Do pass `prefix`; there is no default (`ATOMI_` is an example).
- Do nest with `__`: `ATOMI_SERVER__MAX_RETRIES` matches `maxRetries`,
  `MaxRetries`, `max_retries` or `max-retries`.
- Do encode lists as indexed keys: `ATOMI_SERVER__TAGS__0`, `__1`, …
- Don't put JSON or comma lists in env.
- Don't hand-roll `Number(process.env.X)`; the loader coerces through zod.
- Don't rely on an empty env value: blank means unset and keeps the file value.
- Keep secrets blank in YAML; they arrive as runtime env. Declare secrets `z.string().min(1)`.
- Don't set `app.landscape` from env; pass `landscape` to the loader.
- String fields keep env text as-is (`0123` stays `0123`); number and boolean
  fields are parsed by their schema type.
- Declare booleans `z.boolean()` or `z.stringbool()`, never `z.coerce.boolean()`;
  env booleans must be `true` or `false`.

## Testing (`/test-helper`)

- `InMemoryConfigSource` — plain-object tiers, no files and no `process.env`.
- `LandscapeConfigSource` — an in-memory source whose base names a landscape.
- `ConfigStubBuilder(registry, { prefix })` — a validated `Config` built by the
  real loader; `prefix` is required.
- `ConfigAssertions` — `expectValid` / `expectInvalid` over a stub builder.

Run one behavioural suite against both `YamlConfigSource` and
`InMemoryConfigSource` for real-vs-fake parity. See `assets/test-helper.md`.
