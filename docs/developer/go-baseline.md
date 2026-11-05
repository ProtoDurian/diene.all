# Go baseline

This repository is the Go language foundation inherited by Go services,
operators, and library templates. It adds language machinery only; application
behavior, observability wiring, environment profiles, and publishing belong to
downstream nodes.

## Toolchain

The Nix shells provide Go (from the AtomiCloud registry, which pins the patch
level), golangci-lint, govulncheck, deadcode, staticcheck, gofumpt and
gotestsum.

## Repository shape

- `lib/` contains pure domain packages.
- `adapters/` contains dependency implementations.
- `testhelper/` ships consumer-facing fakes; there is no `cmd/`: a library has no
  composition root ([Go library baseline](go-lib-baseline.md)).
- `tests/unit/` imports domain packages only through their public API.
- `tests/int/` proves adapters against real dependencies with
  testcontainers-go.
- `tests/meta/` proves the `testhelper` package through its public API.

The Note/Redis code is a replaceable sample fenced by `DOMAIN WIRING` and
`END DOMAIN WIRING` comments in every `lib/note/*.go` file,
`adapters/kv/redis.go`, and `testhelper/memory_store.go`, with matching boundaries in
`tests/unit/note/note_test.go`, `tests/int/kv/redis_test.go`, and
`tests/meta/testhelper/memory_store_test.go`. Downstream templates may replace only the bytes
inside those fences while retaining the same gates and tier boundaries.

## Commands

- `task setup` installs modules and synchronizes vendored skills.
- `task build` compiles every package of the module.
- `task typecheck` compiles source packages without running tests.
- `task test`, `task test:unit`, `task test:int`, and `task test:meta` run the
  tiered suites.
- `task test:coverage`, `task test:unit:coverage`, `task test:int:coverage`,
  and `task test:meta:coverage` enforce the scoped ledgers.
- `task test:unit:watch` watches the unit tier.
- `task vuln` scans dependencies with govulncheck.
- `task deadcode:strict` runs the four blocking staticcheck/deadcode passes:
  whole repository and production only, for each tool.
- `task deadcode` writes the nonblocking LLM review feed to
  `reports/deadcode-llm.txt`.
- `task validate` runs the library gates.
- `task up` and `task down` manage the local Redis dependency.

There is deliberately no `task dev`: this base is not a long-running server, so
an Air hot-reload loop would add machinery without a real use case.

## Test and coverage law

Every `*_test.go` file must declare a package ending in `_test`, and
`export_test.go` is forbidden. Unit coverage includes only `lib/**` and must be
100%. Integration coverage includes only `adapters/**` and must be 100% in this
minimal base. The checked-in ledger is `.config/go-base.coverage.yaml`. Each tier
writes its own profile: `coverage/unit/coverage.out`,
`coverage/int/coverage.out` and `coverage/meta/coverage.out`.

## Deadcode and vulnerability law

Four independently invoked strict components cover unused code: staticcheck and
deadcode each run once with test analysis/reachability enabled and once against
production packages only. The production deadcode component therefore rejects
a symbol reachable only from tests. None of the components has an exclusion
list. Govulncheck is a blocking CI-only job; its negative proof routes a pinned
vulnerable fixture through a deterministic scanner double, while the healthy
path uses the real vulnerability database.

## Template-maintenance boundary

Downstream authors may adapt package/module identity, sample domain code,
coverage thresholds after adding real surface.
They must preserve black-box tests, tier scoping,
all four staticcheck/deadcode components, the CI-only vulnerability gate, and
generated hook/probe coverage.
