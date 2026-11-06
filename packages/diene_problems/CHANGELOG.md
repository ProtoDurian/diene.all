# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## Unreleased (0.0.0)

Breaking changes:

- `Problem.data` is now nullable and defaults to `null`. A problem without data
  omits the `data` member on the wire instead of sending `{}`; `fromJson` reads
  a missing, `null` or non-object `data` as no data.
- `ProblemType.dataSchema` and `CatalogEntry.dataSchema` are now nullable; `null`
  means the problem carries no data and publishes the schema `{"not":{}}`.
- `CatalogEntry.toCrdContent()` renders the data schema under `schema`, not
  `data`, matching the Problem CR entry shape.
- `validation_error` data is now an `issues` list; each issue has a `path`
  list, a `message` and an optional `code`.
- `entity_not_found` and `conflict` data are now `{ entityType, id }`, both
  required strings.
- `problemTypeUri` accepts only the `http` and `https` schemes, versions from
  `v1` up (`v0` is rejected) and wire ids of at most 63 characters.
- `r14WireId` is removed; wire ids are snake_case everywhere.
- The generated release projection (`package:diene_problems/c0_problem.dart`,
  `c0ProblemContract` and its types) is removed. Conformance is now checked by
  local fixtures in the package's own test suite.
- `ProblemMatcherError` messages for `data` now compare nested maps by key
  presence as well as value.

Added:

- `ProblemCatalog.toProblemResource(version:)` emits one Problem CR per
  platform, service, module, landscape and version row, named
  `{service}.{module}.{landscape}.{version}` with dots, with its problems sorted
  by id. It throws `ProblemResourceError` for a non-https portal, a field that
  is not a DNS-1123 label, a bad version, an entry built for another row, or an
  invalid or repeated endpoint.
- `noProblemDataSchema`, the schema published for a data-less problem.
- `expectProblem(..., noData: true)` asserts a problem carries no data.
- The package moves to the `ProtoDurian/diene.dart_problems` repository.

## 0.1.1

- Supersedes the retracted bootstrap `0.1.0`; that version is never reused.
- The type-URI builder enforces snake_case wire ids, `v<n>` versions and
  canonical hosts.
- Every shipped wire id is snake_case: `validation_error`, `entity_not_found`,
  `invalid_json`, `local_error`.

## 0.1.0

- Initial release: the RFC 9457 envelope with `data` and `recoverable`, the
  type-URI builder, the typed registry with the generic baseline, `fromObject`,
  `LocalError`, the per-endpoint catalog export and a dependency-light
  `test_helper.dart`.
