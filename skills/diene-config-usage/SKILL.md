---
name: diene-config-usage
description: Use when consuming @atomicloud/diene.config — registering config blocks, running the 4-tier loader, the build-time (/build-time) variant, env-override rules, or faking config in tests via /test-helper.
---

# Diene Config usage

Import only the package root, `/build-time` or `/test-helper`; never copy the
implementation or reach into `src/` or `dist/`. The full contract is the
[config standard](https://github.com/AtomiCloud/diene.bun-config/blob/main/docs/standards/config/index.md).

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

## Env-override rules

- Do pass `prefix`; there is no default (`ATOMI_` is an example).
- Do nest with `__`: `ATOMI_SERVER__MAX_RETRIES` matches `maxRetries`,
  `MaxRetries`, `max_retries` or `max-retries`.
- Do encode lists as indexed keys: `ATOMI_SERVER__TAGS__0`, `__1`, …
- Don't put JSON or comma lists in env.
- Don't hand-roll `Number(process.env.X)`; the loader coerces through zod.
- Don't rely on an empty env value: blank means unset and keeps the file value.
- Keep secrets blank in YAML; they arrive as runtime env.

## Testing (`/test-helper`)

- `InMemoryConfigSource` — plain-object tiers, no files and no `process.env`.
- `LandscapeConfigSource` — an in-memory source whose base names a landscape.
- `ConfigStubBuilder` — a validated `Config` built by the real loader.
- `ConfigAssertions` — `expectValid` / `expectInvalid` over a stub builder.

Run one behavioural suite against both `YamlConfigSource` and
`InMemoryConfigSource` for real-vs-fake parity. See `assets/test-helper.md`.
