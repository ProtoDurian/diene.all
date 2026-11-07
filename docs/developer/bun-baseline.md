---
id: bun-baseline
title: Releaser Bun Baseline
---

# Releaser Bun baseline

This repository is a materialized Bun/TypeScript CLI product. General
engineering rules remain in `docs/standards/`; this page records the local
toolchain and test boundaries.

## Local commands

- `pls setup` installs the locked Bun dependencies after synchronizing vendored
  package skills.
- `pls lint` runs every generated pre-commit hook.
- `pls test`, `pls test:unit`, `pls test:int`, `pls test:meta`, and
  `pls test:sit` run the test tiers without coverage through
  `scripts/local/test.sh <tier>`; SIT drives the freshly compiled binary.
- `pls test:coverage`, `pls test:unit:coverage`,
  `pls test:int:coverage`, and `pls test:sit:coverage` write scoped LCOV
  artifacts. SIT coverage uses the in-process driver only.
- `pls test:watch` watches the unit tier.
- `pls build` bundles the `package.json` `bin` entry to `dist/releaser.js`.
- `pls compile` emits `releaser-linux-x64-baseline`,
  `releaser-linux-arm64`, and `releaser-darwin-arm64` under `dist/bin/`.
- `pls deadcode` runs the two non-blocking LLM-review Knip configurations.
- `pls run -- <args>` executes the source entry point.
- `pls preview -- <args>` compiles and executes this host's standalone binary.

Each tier task is a one-line call to `scripts/local/test.sh`, and `pls clean`
calls `scripts/local/clean.sh`.

There are no sample dependency, `up`/`down`, probe-matrix, or Docker tasks.

## Architecture and quality gates

The composition root is `bin/releaser.ts`. Pure business logic and ports live in
`src/lib`; concrete Git, filesystem, HTTP, process, configuration, and terminal
implementations live in `src/adapters`.

treefmt runs Biome to format TS, JS and JSON in the style set in `biome.json`;
Prettier formats only Markdown and YAML. The Biome hook only lints. TypeScript
uses strict no-emit typechecking. Knip has four dead-code modes, none with ignore or exclude lists:

- `knip.json`: blocking hook over source and tests, so dead test code fails too.
- `knip.production.json`: blocking `--production` hook from `bin/releaser.ts`
  that ignores test usage, so a file only tests use fails.
- `knip.llm.json`: non-blocking repository review for LLMs.
- `knip.production.llm.json`: non-blocking production review for LLMs.

## Test and coverage tiers

- `.config/bun-base.coverage.yaml` lists the tiers (`unit`, `int`, `meta`,
  `sit`), each with its test folder and coverage scope; `scripts/ci/test.sh <tier>`
  and `scripts/local/test.sh <tier>` read it.
  A tier with no test files passes and writes no coverage file.
- Unit tests cover the pure library under `src/lib/**`.
- Integration tests use temporary directories, scratch Git repositories, local
  bare remotes, and fake HTTP only, and cover `src/adapters/**`.
- SIT runs the same user journeys through either the in-process composition seam
  or the freshly compiled Linux x64 binary.
- No test contacts GitHub or publishes an artifact.

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
