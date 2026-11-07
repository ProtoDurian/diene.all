# Go library baseline

This template publishes the Go module `github.com/ProtoDurian/diene.go-lib`. The
module path is the mirror repository path. A library generated from it replaces
the final `go-lib` token with its own name in `go.mod`, `.config/go-lib.yaml`,
imports, `README.md` (text and badges), the API baseline fixture,
`tests/fixtures/deadcode-consumer.go.txt` and this document. Mirrors are single-module
unless a library proves it needs more.

It builds on [the Go baseline](go-baseline.md), minus the binary: there is no
`main` or `cmd/` package, no compiled artifact, no `run`/`preview` task and no
system-integration tier.

## Package and API shape

- Keep public packages small and cohesive. Non-API code lives in `internal/<name>`.
- No private logic. Private fields are fine; an unexported helper with behaviour
  becomes an injected service or an `internal/<name>` package, tested through its
  exported surface. Nondeterminism is reached through injected seams.
- Every exported symbol has a doc comment (`task validate`, export-docs mode).
- `Example*` functions in the package directory are the living usage docs; they
  compile and their `// Output:` is checked.
- Tests are table-driven where a function has more than one case.
- Every test is a black-box `package <pkg>_test`; `export_test.go` is forbidden
  (pre-commit hook `a-go-black-box`).

The README's library section carries one badge block: pkg.go.dev reference, the mirror's `CI`
workflow status and the license.

The `lib/note` sample and the `adapters/kv` Redis adapter sit between
`DOMAIN WIRING` fences for wholesale replacement.

## Test pyramid and TestHelper

| Tier | Tests            | Covers           | Target |
| ---- | ---------------- | ---------------- | ------ |
| unit | `tests/unit/...` | `lib/...`        | 100%   |
| int  | `tests/int/...`  | `adapters/...`   | 100%   |
| meta | `tests/meta/...` | `testhelper/...` | 100%   |

`testhelper` ships consumer-facing fakes. Add one only when consumers would
otherwise repeat fakes, assertions, seams or complex construction, and dogfood it
in its own meta tests. A library with no `testhelper` package skips the meta tier.

## Library gates

`task validate` runs `scripts/local/pkg-validate.sh` (CI job `Package Validation`);
each mode can run alone (`task validate -- vet`):

| Mode          | Gate                                                                  |
| ------------- | --------------------------------------------------------------------- |
| `module-path` | `go.mod` equals `.config/go-lib.yaml` `module` and the mirror path    |
| `vet`         | `go vet ./...`                                                        |
| `api-compat`  | `gorelease` against the sealed baseline `tests/fixtures/api-baseline` |
| `export-docs` | revive `exported` over every package (`.golangci.docs.yaml`)          |
| `examples`    | every `Example*` compiles and passes                                  |

Production dead code is measured from a consumer of the public API,
`tests/fixtures/deadcode-consumer.go.txt`: a library has no `main` of its own.
Extend that consumer whenever the public API grows.

## Compatibility and major versions

`gorelease` is the only API-compatibility tool. The fixture is the accepted v1
surface; removing or renaming an export is refused. Refresh the fixture only at
an accepted release boundary. A breaking release needs a `/v2` module path; that
migration is outside this v1 template.

## Release and publication

Semantic release computes the version and changelog and creates the `vX.Y.Z` tag
on the mirror. Go has no manifest version and no registry push, so there is no
bump script: the tag is the release and the Go proxy serves it. The tag-triggered
`CD` workflow (`scripts/ci/publish.sh`) refuses any tag that is not exactly
`vX.Y.Z`, re-checks the module path, builds the module and resolves the tag into
a clean consumer through `https://proxy.golang.org`.
