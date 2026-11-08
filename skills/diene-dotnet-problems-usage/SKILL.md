---
name: diene-dotnet-problems-usage
description: Use AtomiCloud.Diene.Problems and its TestHelper in .NET services. Use when defining, registering, rendering, exporting, or asserting typed RFC 9457 problems.
---

# Diene .NET Problems usage

Use the package as a registration-first problem boundary. Consumer services own
their domain problem classes; this library owns stable identity, catalog policy,
wire rendering, and export mechanics.

## Register the catalog

1. Implement `IDomainProblem` with a public parameterless constructor. Keep
   `Id`, `Title`, `Detail`, and `Version` metadata `[JsonIgnore]`d and expose only
   the typed payload to serialization.
2. Call `AddAtomiProblems` once in the composition root. Register `AddBaseline()`
   and every consumer problem with status, recoverability, and affected
   `ProblemEndpoint` values.
3. Add `UseExceptionHandler()` to the ASP.NET Core pipeline.

Never rely on implicit scanning. `AddFromAssembly` is allowed only as an explicit,
caller-filtered registration choice.

## Use the generic catalog

`AddBaseline()` registers `validation_error` (400), `entity_not_found` (404),
`conflict` (409), `unauthenticated` (401), `unauthorized` (403) and
`invalid_json` (400), plus the .NET-only `multiple_entity_not_found` and
`entity_conflict`. Throw `Conflict` for new 409s; `entity_conflict` is superseded
and kept for one release only.

- `entity_not_found` and `conflict` carry `{ entityType, id }`. Prefer the
  `(detail, entityType, id)` constructors.
- `validation_error` carries `{ issues: [{ path, message, code? }] }`. Build it
  from `ValidationIssue` values; the dictionary form splits fields on `.`.
- The other three carry no data. Any problem, generic or yours, whose payload
  has no properties renders without `data` and exports the schema `{"not":{}}`.

## Preserve the single URI source

Resolve and call `IProblemTypeUriBuilder` for every problem type URI. Never format
or copy the ErrorPortal URI template in a controller, transformer, test, or other
library. Wire ids are snake_case and versions use the `v1` form.

## Carry and render failures

Use `ProblemGuard` or `ToErr<T>()` while a failure remains expected domain data.
Use `ToException()` only at a framework boundary. An unregistered or type-spoofed
problem is a catalog defect: preserve the library's logged 500 behavior instead
of adding a fallback status.

## Assert contracts

Reference `AtomiCloud.Diene.Problems.TestHelper` only from test code. Assert
domain identity with `BeProblem<T>()`, `HaveId`, and `HaveVersion`; Result errors
with `BeErrProblem<T>()`; and HTTP responses with `BeRfc9457`, `HaveType`,
`HaveStatus`, `HaveData`, `HaveNoData`, and `BeRecoverable`. Prove new assertions with both a
known-good and known-bad meta test.

## Export Problem resources

Resolve `ProblemResourceEmitter` from the same registered service provider. Emit
one resource per platform/service/module/landscape/version row. The module comes
from the ErrorPortal identity; an explicit module must match it. The resource is
named `{service}.{module}.{landscape}.{version}`; every identity field must already
be a DNS-1123 label.
Let the consuming service's build task write the serialized canonical JSON/YAML
into its chart.
