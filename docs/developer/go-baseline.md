# Go baseline

This repository is the Go language foundation inherited by Go services,
operators, and library templates. It adds language machinery only; application
behavior, observability wiring, environment profiles, and publishing belong to
downstream nodes.

## Toolchain

The Nix shells provide Go (from the AtomiCloud registry, which pins the patch
level), golangci-lint, govulncheck, deadcode, staticcheck, gofumpt and
gotestsum. Dates and times of day use `cloud.google.com/go/civil`, pinned in
`go.mod` (`pins.go` keeps it there until code imports it).

## Repository shape

- `lib/` contains pure domain packages.
- `adapters/` contains dependency implementations.
- `cmd/go-base/` is the single composition root and wires concrete adapters
  explicitly.
- `tests/unit/` imports domain packages only through their public API.
- `tests/int/` proves adapters against real dependencies with
  testcontainers-go.
- `tests/sit/` exercises compiled artifacts from a client's perspective.

## Commands

- `task setup` installs modules and synchronizes vendored skills.
- `task build` creates `dist/go-base`.
- `task typecheck` compiles source packages without running tests.
- `task test`, `task test:unit`, `task test:int`, and `task test:sit` run the
  tiered suites; `task test:sit` runs the compiled-artifact Redis journey.
- `task test:coverage`, `task test:unit:coverage`, and
  `task test:int:coverage` enforce the scoped ledgers.
- `task test:unit:watch` watches the unit tier.
- `task vuln` scans dependencies with govulncheck.
- `task deadcode:strict` runs the four blocking staticcheck/deadcode passes:
  whole repository and production only, for each tool.
- `task deadcode` writes the nonblocking LLM review feed to
  `reports/deadcode-llm.txt`.
- `task run -- slug "Hello World"` runs from source.
- `task preview -- slug "Hello World"` runs the compiled artifact.
- `task up` and `task down` manage the local Redis dependency.

There is deliberately no `task dev`: this base is not a long-running server, so
an Air hot-reload loop would add machinery without a real use case.

## Test and coverage law

Every `*_test.go` file, `export_test.go` included, must declare a package ending
in `_test`; golangci-lint's `testpackage` linter enforces it.
Unit coverage includes only `lib/**` and must be
100%. Integration coverage includes only `adapters/**` and must be 100% in this
minimal base. The checked-in ledger is `.config/go-base.coverage.yaml`. Each tier
writes its own profile: `reports/unit/coverage.out` and
`reports/integration/coverage.out`.

## Deadcode and vulnerability law

Four independently invoked strict components cover unused code: staticcheck and
deadcode each run once with test analysis/reachability enabled and once against
production packages only. The production deadcode component therefore rejects
a symbol reachable only from tests. None of the components has an exclusion
list. Govulncheck is a blocking CI-only job.

## Docker

The Dockerfile builds a static binary and runs it from
`gcr.io/distroless/static-debian12:nonroot` as UID/GID 65532.

## Helm

The root chart remains a minimal all-yes Helm surface and is intentionally
independent of downstream service chart design.

## Template-maintenance boundary

Downstream authors may adapt:

- package/module identity
- sample domain code
- coverage thresholds after adding real surface
- the Docker entrypoint
- chart metadata

They must preserve:

- black-box tests
- tier scoping
- all four staticcheck/deadcode components
- the CI-only vulnerability gate
- one composition root
- distroless nonroot runtime policy
- generated hook/probe coverage
