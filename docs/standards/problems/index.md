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
`data` extension member.

- A problem registered with a Zod `dataSchema` always carries `data`, typed by
  that schema.
- A problem registered without a `dataSchema` never carries `data`: the member
  is omitted, never `null` and never an empty placeholder.
- `status` is an error status: an integer from 400 through 599.

`ProblemFactory.createProblem(entry, init)` mints a Problem from a registered
entry. It parses `init.data` through the entry's schema, refuses `data` for an
entry without one, and only writes `detail` and `instance` when they are given.
`init.status` may override the registered status; it must also be from 400
through 599.

## Versioned type URIs

`ProblemTypeUriBuilder.buildProblemTypeUri(portal, version, id)` is the only
place that formats a type URI:

```text
{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}
```

- Every service-tree value comes from the service's `ErrorPortalConfig`, never
  from a literal in code.
- `scheme` is `http` or `https`, checked at runtime because the config comes
  from YAML or the environment.
- `version` is `v1`, `v2`, … (no `v0`, no leading zeros). A version bump
  deliberately mints a new Problem type; never change what a published
  version means.
- `id` is snake_case, at most 63 characters.
- The host must be a canonical lowercase `host` or `host:port`.

Consumers never format a type URI themselves. `ProblemRegistry` calls the
builder on `register`, and `ProblemResourceEmitter` calls it to check each
row.

## Registry

Construct one `ProblemRegistry` from the service's `ErrorPortalConfig` and
register each definition: `id`, `title`, `status`, `recoverable`, `version` and
an optional Zod `dataSchema`. The registry binds the type URI, renders the
`data` JSON Schema, freezes the entry and is the enumerable source for
publication. A schema JSON Schema cannot express (for example `z.date()`) is
refused at registration. `register` throws a `ProblemRegistryError`;
`tryRegister` returns the same failure as a `Result`. `get`, `require` and
`list` look entries up and enumerate them by numeric version, then id.

## Transformer

`ProblemTransformer` turns unknown failures into Problems:

- The options follow the fallback entry: a fallback with a data schema needs a
  `fallbackData` mapper typed by that schema, and a fallback without one takes
  none. The constructor refuses a mismatch for JavaScript callers.
- `fromError(unknown)` walks nested `problem`, `error` and `cause` members
  (stopping on cycles) to find a Problem. With none, it mints the configured
  fallback from the original thrown value, which is what `fallbackData` and
  `instance` receive. The `detail` is the first message found walking the
  chain from that value (its own message first), else a generic detail.
- `fromHttpError(response)` keeps a direct or nested Problem body, and
  otherwise mints the fallback from the JSON, text or empty body, with the
  first message found in it as the `detail`. The response
  status replaces the Problem's status only when it is an error status;
  otherwise the body's or the entry's status stays.
- A found Problem is rebuilt from `type`, `title`, `status`, `detail` and
  `instance` when they are strings, and `data` when present. Every other
  member is dropped.
- `instance` only ever comes from the configured `instance` option, never from
  the upstream request URL.

`ProblemGuard.isProblem` is the shared envelope check: `type` and `title`
strings and an error `status`; `data` is optional.

## Generic catalog

The package ships exactly six portable problems.
`GenericProblemCatalog.registerGenericProblems(registry, version = 'v1')`
registers them, and `createGenericProblemRegistry(portal, version = 'v1')`
returns a registry holding them. They follow the row's version, so a service
on `v2` registers the generics at `v2` beside its own problems; ids, statuses,
flags and schemas never change. They share the registry's id namespace with
the service's own problems, so a service cannot register a second `conflict`.
Domain problems live in the consuming service, never here.

| Export            | id                 | status | recoverable | `data`                                     |
| ----------------- | ------------------ | ------ | ----------- | ------------------------------------------ |
| `ValidationError` | `validation_error` | 400    | true        | `issues[]` of `{ path[], message, code? }` |
| `EntityNotFound`  | `entity_not_found` | 404    | false       | `{ entityType, id }`                       |
| `Conflict`        | `conflict`         | 409    | true        | `{ entityType, id }`                       |
| `Unauthenticated` | `unauthenticated`  | 401    | true        | none (omitted)                             |
| `Unauthorized`    | `unauthorized`     | 403    | false       | none (omitted)                             |
| `InvalidJson`     | `invalid_json`     | 400    | true        | none (omitted)                             |

Every schema is strict. Richer `conflict` fields may only be added later as
optional fields. A problem without data publishes the JSON Schema
`{ "not": {} }`: any present `data` member is invalid.

## Publication

Publication is a build step; there is no live endpoint.

- `ProblemManifestEmitter.emitProblemManifest(registry)` writes the problem
  list plus a JSON Schema per type URI for the erbium informer.
- `ProblemCatalog.declare(entry, { endpoints })` adds the endpoints that can
  return a registered problem. A method is an uppercase HTTP method, a path
  starts with `/`, and a `(method, path)` pair appears once. Every other field
  (`type`, `title`, `status`, `recoverable`, `data` schema) comes from the
  registry, so a generic entry is exported unchanged.
- `ProblemResourceEmitter.emitProblemResource(catalog, row)` writes one
  `Problem` resource per `(platform, service, module, landscape, version)`
  row. The spec repeats all five identity fields and lists `problems[]` as
  `{ id, type, title, status, recoverable, schema, endpoints }`.

The resource identity must be valid Kubernetes:

- `platform`, `service`, `module` and `landscape` are DNS-1123 labels
  (lowercase letters, digits and `-`, starting and ending with a letter or
  digit, at most 63 characters); `version` is `v1`, `v2`, ….
- `metadata.namespace` is the platform. `metadata.name` is
  `service.module.landscape.version`, at most 253 characters. Labels carry no
  dot, so two rows never share a name.
- The registry portal must be `https`: the published resource only admits
  `https` type URIs. `http` stays legal for in-process type URIs.
- The four segments must equal the registry portal's, and every entry's type
  URI must belong to the row.
- A catalog that declares nothing emits a valid empty row (`problems: []`).

Commit the emitted rows to the service's primordial chart and drift-check them
in CI. erbium merges the rows and publishes the edge catalog; frontends read
that edge copy, never Primordial. An uncatalogued failure stays a 5xx until
the next release declares it, re-emits the row and lets erbium republish.

## TestHelper

`@atomicloud/diene.problems/test-helper` exports `ProblemTestHelper`:

- `expectProblem(actual).toBe(entry, options?)` checks type, title, status and
  the entry's data (schema-valid, or absent when the entry has no schema), and
  optionally exact `status`, `detail`, `instance` and `data`. It throws one
  `ProblemAssertionError` listing every difference, including when `actual` is
  not a Problem at all, and returns the Problem typed by the entry's schema.
- `buildProblem(entry, init)` and `buildProblemFromRegistry(registry, id,
init, version?)` mint valid Problems for consumer tests.

The helper has no test-framework dependency, so it works with any runner.
