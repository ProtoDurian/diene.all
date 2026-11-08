---
name: diene-go-errors-problems-usage
description: Use the diene Go errors-problems library (RFC 9457 problem errors, the type-URI builder, the generic catalog, the Problem resource export and the TestHelper assertions).
---

# Diene Go errors-problems usage

The package docs and compiling examples are the reference: `go doc
github.com/ProtoDurian/diene.go-errors-problems/lib/problem` and `go doc
github.com/ProtoDurian/diene.go-errors-problems/testhelper` (or pkg.go.dev).
This skill only lists the rules the examples assume.

## Library (`lib/problem`)

- Return failures as `(T, error)` where the error is a `*problem.Error`
  (`problem.NewError`, `problem.WrapError`). Recover it with `errors.As`.
- Build every type URI with `problem.TypeURI` (or `Registry.TypeURIFor`); never
  format the URI yourself. The `{version}` segment is part of the identity.
- Register the generic catalog with `problem.RegisterGenerics`. Its wire ids are
  snake_case: `validation_error`, `entity_not_found`, `conflict`,
  `unauthenticated`, `unauthorized`, `invalid_json`.
- A business rule is a problem your service declares: a `problem.Type` with its
  own id, status (often 422), `Recoverable` flag and `DataSchema`. Register it
  and raise it with `Registry.NewProblem(id, data)`. There is no catch-all
  domain problem.
- A problem with no data leaves `Data` nil: the wire form has no `data` member
  and the catalog publishes the schema `{"not":{}}`.
- Publish the catalog with `Catalog.ToResource(identity)`. It returns the
  `Problem` resource named `{service}.{module}.{landscape}.{version}` and refuses
  a row that does not match the catalog portal.
- `problem.FromObject` turns any value into a problem. An error nobody
  catalogued becomes a plain 5xx; add it to the catalog and re-emit the resource.

## TestHelper (`testhelper`)

- `testhelper.AssertError(t, err, testhelper.ExpectID("entity_not_found"),
testhelper.ExpectStatus(404), testhelper.ExpectData(want))` recovers and checks
  the problem a `(T, error)` result carries.
- `CheckProblem` / `CheckError` return the first mismatch instead of failing.
- `SampleErrorPortal` and `SampleProblem` give valid fixtures.
