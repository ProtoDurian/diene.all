# Typed problem contract

<!-- ### lib-dotnet-problems -->
<!-- #### source: lib/dotnet/problems -->

`AtomiCloud.Diene.Problems` owns the portable typed-problem contract and the
framework boundary that renders it. A consumer owns its domain problem classes,
registers them explicitly, and uses the resulting catalog as the single runtime
and export source of truth.

## Scope

| Surface                        | Responsibility                                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `IDomainProblem` and `Problem` | Separate typed domain data from the RFC 9457 wire envelope and its `data` and `recoverable` extensions.             |
| `ProblemTypeUriBuilder`        | Build the only supported versioned type URI from plain ErrorPortal and LPSM values.                                 |
| `ProblemCatalogBuilder`        | Register typed problems, statuses, recoverability, and affected endpoints explicitly.                               |
| Baseline catalog               | Supply the six generic problems, plus two .NET-only extras, with snake_case ids and default status policy.          |
| `ProblemExporter`              | Derive payload JSON Schema from the .NET serialization contract with the BCL exporter.                              |
| `ProblemResourceEmitter`       | Emit one deterministic `atomi.cloud/v1alpha1` Problem resource for one catalog version.                             |
| `ProblemGuard` and adapters    | Carry expected failures in `Result<T, IDomainProblem>` and convert them to exceptions only at framework boundaries. |
| ASP.NET Core adapter           | Register `IExceptionHandler`, `AddProblemDetails`, and RFC 9457 rendering through `AddAtomiProblems`.               |
| TestHelper                     | Assert typed identity, exceptions, Results, envelopes, and full HTTP responses.                                     |

## Runtime rules

Registration is mandatory. A type that is absent from the catalog, or an object
that spoofs a registered `(version, id)` with the wrong concrete type, is treated
as an internal catalog-loop failure: the response status is 500, its type is
`about:blank`, and `ProblemCatalog` logs an error. A missing registration must
never silently become a consumer-visible 4xx response.

Wire ids are snake_case and versions use the `v1` form. Their exact patterns are:

```text
id: ^[a-z][a-z0-9_]*$
version: ^v[0-9]+$
```

The canonical URI shape is:

```text
{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}
```

Only `IProblemTypeUriBuilder` may expand that shape. Consumers, controllers, and
other engine libraries inject the builder instead of copying the template.

Problem metadata (`id`, `title`, `detail`, and `version`) is excluded from typed
payload serialization. The HTTP envelope carries the RFC 9457 members plus the
serialized payload in `data`, the catalog policy in `recoverable`, and arbitrary
extensions such as `traceId`.

## Generic catalog `v1`

`ProblemCatalogBuilder.AddBaseline()` registers the generic catalog that every
language ships, with the same ids, statuses and wire `data`:

| id                 | status | recoverable | wire `data`                                                          |
| ------------------ | ------ | ----------- | -------------------------------------------------------------------- |
| `validation_error` | 400    | true        | `{ "issues": [ { "path": [..], "message": "..", "code"?: ".." } ] }` |
| `entity_not_found` | 404    | false       | `{ "entityType": "..", "id": ".." }`                                 |
| `conflict`         | 409    | true        | `{ "entityType": "..", "id": ".." }`                                 |
| `unauthenticated`  | 401    | true        | none                                                                 |
| `unauthorized`     | 403    | false       | none                                                                 |
| `invalid_json`     | 400    | true        | none                                                                 |

It also registers two .NET-only extras: `multiple_entity_not_found` (404) and
`entity_conflict` (409). `entity_conflict` is superseded by `conflict` and stays
registered for one more release so existing throwers keep a catalogued 409.

A `ValidationIssue` path is a list of segments; the dictionary constructor of
`ValidationError` splits each field on `.` (an empty field is the empty path).
`code` is omitted when absent.

A problem that serializes to an object with no properties has no data: its
envelope omits `data` (never `null` or `{}`), and its exported schema is
`{"not":{}}`. This applies to consumer problems too. An uncatalogued problem
renders a plain 500 without `data`.

This release changes the wire `data` of `entity_not_found`, `validation_error`,
`unauthorized` and `invalid_json`, adds `conflict`, and keeps `entity_conflict`
for one release. The previous .NET properties (`RequestIdentifier`, `TypeName`,
`AssemblyQualifiedName`, `Errors`, `Granted`, `Required`, `InvalidString`) stay
public for binary compatibility but no longer serialize. The release version
is the owner's call.

## Catalog and Problem resources

Each service registers its baseline and domain-specific problems in its
composition root. `ProblemExporter` derives the payload schema using
`System.Text.Json.Schema.JsonSchemaExporter`, honouring nullable annotations and
`[JsonRequired]`, and lifts `DescriptionAttribute`
values into schema descriptions. `ProblemResourceEmitter` validates portal
identity, catalog version, and exported type URI before producing canonical JSON
that is valid YAML 1.2.

A Problem resource row is identified by five fields: platform, service, module,
landscape and version. The module comes from the ErrorPortal identity; an
explicit module must equal it. `metadata.name` is
`{service}.{module}.{landscape}.{version}` joined with dots, so `a-b` + `c` and
`a` + `b-c` never collide. Each field, and the platform, must already be a
DNS-1123 label (no slugifying), and the name must fit in 253 characters, or
emitting throws. A spec read back without `module` gets an empty module.
Emitting needs an https ErrorPortal, because the Problem CRD accepts only
https type URIs; envelopes may still use http. `metadata.namespace` is the
platform. The `spec` fields are written in the order
`platform, service, module, landscape, version, problems`, and `problems` is
sorted by id.

The consuming service owns the build task that writes emitted resources into its
primordial chart. This package owns the model and emitter, not that repository
task or chart layout.

## Removed template warts

| Previous behavior                                                 | Current rule                                                                     |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Assembly and namespace scanning selected problems implicitly.     | Registration is consumer-owned; assembly scanning is opt-in and caller-filtered. |
| A hard-coded API route exposed error metadata at runtime.         | Catalog data moves through the Problem custom-resource channel.                  |
| Unknown problems silently fell back to a 4xx response.            | Unknown or spoofed typed problems log loudly and return 500.                     |
| Multiple adapters formatted problem type URIs.                    | One injected builder owns URI construction.                                      |
| The sample coupled integration tests to Redis and Testcontainers. | The integration tier exercises ASP.NET Core in process.                          |

## Deliberately absent

- No runtime error-info controller or catalog endpoint.
- No dependency on a configuration package; composition roots map their own
  settings into `ErrorPortalOption` and `ProblemIdentity`.
- No server-engine or application hosting policy beyond the problem exception
  adapter.
- No implicit global catalog and no custom per-instance recoverability override.
