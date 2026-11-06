# RFC 9457 Problems

`@atomicloud/diene.problems` owns the Bun family's Problem Details machinery:
the envelope, the typed registry, the transformer, the type URI builder, the
publication emitters and the generic catalog. Bridging HTTP responses into a
`Result` belongs to `@atomicloud/diene.api-engine`. No service exposes runtime
error-info endpoints; the catalog publication below replaces them.

Every member is a stateless class with its collaborators injected through the
constructor (each has a working default). There are no free functions.

## Envelope

A `Problem<TData>` (alias `ProblemDetail<TData>`) carries the RFC 9457 members
`type`, `title`, `status`, optional `detail` and optional `instance`, plus the
`data` extension member. `data` is always present and is typed by the Zod
schema the Problem was registered with. A Problem with no payload carries an
empty object, never `null`.

`ProblemFactory.createProblem(entry, init)` mints a Problem from a registered
entry. It parses `init.data` through the entry's schema and only writes
`detail` and `instance` when they are given. `init.status` may override the
registered status for transport mapping; it must still be an integer from 100
through 599.

## Versioned type URIs

`ProblemTypeUriBuilder.buildProblemTypeUri(portal, version, id)` is the only
place that formats a type URI:

```text
{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}
```

- Every service-tree value comes from the service's `ErrorPortalConfig`, never
  from a literal in code.
- `version` is `vN`. A version bump deliberately mints a new Problem type;
  never change what a published version means.
- `id` is snake_case.
- The host must be a canonical lowercase `host` or `host:port`.

Consumers never format a type URI themselves. `ProblemRegistry` calls the
builder on `register`, and `ProblemResourceEmitter` calls it to check each
row.

## Registry

Construct one `ProblemRegistry` from the service's `ErrorPortalConfig` and
register each definition: `id`, `title`, `status`, `recoverable`, `version` and
a Zod `dataSchema`. The registry binds the type URI, freezes the entry and is
the enumerable source for publication. `register` throws a
`ProblemRegistryError`; `tryRegister` returns the same failure as a `Result`.
`get`, `require` and `list` look entries up and enumerate them by version,
then id.

## Transformer

`ProblemTransformer.fromError(unknown)` returns an existing Problem unchanged,
unwraps nested `problem`, `error` and `cause` members (stopping on cycles),
and otherwise mints the configured fallback. `fromHttpError(response)` keeps a
direct or nested Problem body with the transport status, and otherwise mints
the fallback from the JSON, text or empty body. `ProblemGuard.isProblem` is
the shared envelope check.

## Generic catalog

The package ships exactly six portable problems, all at version `v1`.
`GenericProblemCatalog.registerGenericProblems(registry)` registers them, and
`createGenericProblemRegistry(portal)` returns a registry holding them. They
share the registry's id namespace with the service's own problems, so a
service cannot register a second `conflict`. Domain problems live in the
consuming service, never here.

| Export            | id                 | status | recoverable | `data`                                     |
| ----------------- | ------------------ | ------ | ----------- | ------------------------------------------ |
| `ValidationError` | `validation_error` | 400    | true        | `issues[]` of `{ path[], message, code? }` |
| `EntityNotFound`  | `entity_not_found` | 404    | false       | `{ entityType, id }`                       |
| `Conflict`        | `conflict`         | 409    | true        | `{ entityType, id }`                       |
| `Unauthenticated` | `unauthenticated`  | 401    | true        | none (empty object)                        |
| `Unauthorized`    | `unauthorized`     | 403    | false       | none (empty object)                        |
| `InvalidJson`     | `invalid_json`     | 400    | true        | none (empty object)                        |

Every schema is strict. Richer `conflict` fields may only be added later as
optional fields.

## Publication

Publication is a build step; there is no live endpoint.

- `ProblemManifestEmitter.emitProblemManifest(registry)` writes the problem
  list plus a JSON Schema per type URI for the erbium informer.
- `ProblemCatalog.declare(entry, { endpoints })` adds the endpoints that can
  return a registered problem. Every other field (`type`, `title`, `status`,
  `recoverable`, `data` schema) comes from the registry, so a generic entry is
  exported unchanged.
- `ProblemResourceEmitter.emitProblemResource(catalog, row)` writes one
  `Problem` resource per `(platform, service, module, landscape, version)`
  row. The spec repeats all five identity fields and lists `problems[]` as
  `{ id, type, title, status, recoverable, schema, endpoints }`. It refuses an
  empty catalog and any entry whose type URI does not belong to the row.

Commit the emitted rows to the service's primordial chart and drift-check them
in CI. erbium merges the rows and publishes the edge catalog; frontends read
that edge copy, never Primordial. An uncatalogued failure stays a 5xx until
the next release declares it, re-emits the row and lets erbium republish.

## TestHelper

`@atomicloud/diene.problems/test-helper` exports `ProblemTestHelper`:

- `expectProblem(actual).toBe(entry, options?)` checks type, title, status and
  the registered data schema, and optionally exact `status`, `detail`,
  `instance` and `data`. It throws one `ProblemAssertionError` listing every
  difference and returns the Problem typed by the entry's schema.
- `buildProblem(entry, init)` and `buildProblemFromRegistry(registry, id,
init, version?)` mint valid Problems for consumer tests.

The helper has no test-framework dependency, so it works with any runner.
