---
id: bun-baseline
title: Bun Baseline
---

# Bun Baseline

`bun-base` is the Bun and TypeScript foundation inherited by the Bun sample
family. This page documents only language-layer behavior; general engineering
rules remain in `docs/standards/`.

## Local commands

- `task setup` installs the locked Bun dependencies after synchronizing vendored
  package skills.
- `task lint` runs every generated pre-commit hook.
- `task test`, `task test:unit`, and `task test:int` run the test tiers without
  coverage.
- `task test:coverage`, `task test:unit:coverage`, and
  `task test:int:coverage` write scoped LCOV artifacts.
- `task test:watch` watches the unit tier.
- `task build` bundles `src/index.ts` to `dist/index.js`.
- `task deadcode` runs the two non-blocking LLM Knip views.
- `task run -- <args>` executes the source entry point.
- `task preview -- <args>` rebuilds and executes the bundled artifact.
- `task docker:build` and `task docker:run` build and run the Bun image.
- `task helm:lint` and `task helm:template` retain the inherited Helm axis.

There is no `task dev`, `task up`, or `task down` surface in this base. Hot reload
belongs to runnable descendants, and the integration tier owns its Redis
dependency through Testcontainers.

## Quality gates

Biome is lint-only; treefmt owns formatting. TypeScript uses strict no-emit
typechecking. Knip has four dead-code modes, none with ignore or exclude lists:

- `knip.json`: blocking hook over source and tests, so dead test code fails too.
- `knip.production.json`: blocking `--production` hook from `src/index.ts`
  that ignores test usage, so a file only tests use fails.
- `knip.llm.json`: non-blocking repository review for LLMs.
- `knip.production.llm.json`: non-blocking production review for LLMs.

## Test and coverage tiers

- Unit tests live under `tests/unit/` and cover only `src/lib/**`.
- Integration tests live under `tests/integration/`, use Testcontainers Redis,
  and cover only `src/adapters/**`.
- Both CI entry points require an LCOV artifact, reject paths outside their
  tier ledger, and require every ledger line to be hit.
- Each tier writes its own LCOV file: `reports/unit/lcov.info` and
  `reports/integration/lcov.info`.

Tests use `bun:test`, `describe`/`it`, `// Arrange` / `// Act` / `// Assert`
blocks, and prototype `should` assertions.
Container images are version-pinned without digests.

## Build and runtime

The local build and CI build share `scripts/local/build.sh`. The Dockerfile
uses version-pinned `oven/bun` build and runtime stages, installs from the
frozen lockfile, bundles the sample, and runs as the unprivileged `bun` user.
The sample is stateless classes wired in `src/index.ts`: the domain in
`src/lib/sample/`, pino and Redis in `src/adapters/`. It prints a composed key
by default; `REDIS_HOST` plus `REDIS_PORT` enable a Redis round trip.

The sample logs pino JSON only. Trace-context injection belongs to the
observability payload, which descendants add; this node declares no
`@atomicloud/diene.*` dependency.

## TypeScript standards

Read the TypeScript variants alongside their shared standards:

- [date/time](../standards/datetime/languages/typescript.md)
- [domain-driven design](../standards/domain-driven-design/languages/typescript.md)
- [functional practices](../standards/functional-practices/languages/typescript.md)
- [SOLID principles](../standards/solid-principles/languages/typescript.md)
- [stateless OOP and dependency injection](../standards/stateless-oop-di/languages/typescript.md)
- [testing](../standards/testing/languages/typescript.md)
- [utilities](../standards/utilities/languages/typescript.md)
- [validation](../standards/validation/languages/typescript.md)

## External service / compute cost

- Integration tests and Docker image builds require a Docker runtime.
- Unit, integration, build, Docker, and Helm are separate CI jobs.

## Template maintenance boundary

Downstream templates may adapt package identity, coverage thresholds, the
Docker entry point, badges, and the fenced illustrative `src/` plus `tests/`
sample. They should not fork the inherited task, workflow, release, Nix, lint,
or standards machinery. Shared fixes land at the earliest owning branch and
merge down.
