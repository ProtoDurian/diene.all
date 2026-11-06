# diene_problems

`diene_problems` is the Dart RFC 9457 problem-details library of the Diene
family. It has no runtime dependencies. Import only the barrel:

```dart
import 'package:diene_problems/diene_problems.dart';
```

## Envelope

`Problem` carries the RFC 9457 members `type`, `title`, `status`, `detail` and
`instance`, plus two extensions:

- `data` — the typed payload. Its JSON Schema is published per problem in the
  catalog. A problem without data omits `data` on the wire; it is never sent as
  `null` or `{}`.
- `recoverable` — whether the client may offer a retry.

```json
{
  "type": "https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/entity_not_found",
  "title": "Entity not found",
  "status": 404,
  "detail": "Note 42 does not exist",
  "instance": "/notes/42",
  "recoverable": false,
  "data": { "entityType": "note", "id": "42" }
}
```

## Versioned type URI

`problemTypeUri` is the only place the type URI is formatted:

```text
{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}
```

The coordinates come from an `ErrorPortal` config block. `version` is part of
the problem's identity: bumping it mints a new problem type. The builder throws
`InvalidProblemTypeSegmentError`, naming the bad segment, when:

- `scheme` is not `http` or `https`;
- `host` is not a bare canonical `host` or `host:port`;
- a landscape, platform, service or module segment does not match
  `^[A-Za-z0-9][A-Za-z0-9._-]*$`;
- `version` does not match `^v[1-9][0-9]*$`;
- `id` is not a snake_case wire id of at most 63 characters.

Registry, catalog, transformer, `LocalError` and the TestHelper builders all
call it. Never format the string yourself.

## Registry and generic baseline

A `ProblemType` declares `id`, `title`, `version`, an optional `status`, the
`recoverable` flag and the JSON Schema of its `data` (`null` for none).
`ProblemRegistry` holds a service's types and resolves their URIs.
`GenericProblems` is the baseline every service inherits:

| id                 | status | recoverable | `data`                                     |
| ------------------ | ------ | ----------- | ------------------------------------------ |
| `validation_error` | 400    | true        | `issues[]` of `{ path[], message, code? }` |
| `entity_not_found` | 404    | false       | `{ entityType, id }`                       |
| `conflict`         | 409    | true        | `{ entityType, id }`                       |
| `unauthenticated`  | 401    | true        | none                                       |
| `unauthorized`     | 403    | false       | none                                       |
| `invalid_json`     | 400    | true        | none                                       |

Domain problems are declared by the service that owns them.

## Catalog export to the edge

`ProblemCatalog` declares, per problem, the endpoints that can return it.
`toProblemResource(version:)` emits one `Problem` custom resource for the row
`(platform, service, module, landscape, version)`:

```json
{
  "apiVersion": "atomi.cloud/v1alpha1",
  "kind": "Problem",
  "metadata": { "name": "zinc.api.raichu.v1", "namespace": "nitroso" },
  "spec": {
    "platform": "nitroso",
    "service": "zinc",
    "module": "api",
    "landscape": "raichu",
    "version": "v1",
    "problems": [
      {
        "id": "unauthorized",
        "type": "https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/unauthorized",
        "title": "Unauthorized",
        "status": 403,
        "recoverable": false,
        "schema": { "not": {} },
        "endpoints": [{ "method": "GET", "path": "/notes" }]
      }
    ]
  }
}
```

- The name joins service, module, landscape and version with dots; dashes
  would let two different rows share a name.
- A problem without data publishes the schema `{"not":{}}`.
- Problems are sorted by id. Every entry must have been built for this row.

The service's chart renders this payload; erbium merges the resources and
publishes the error portal at the edge. Clients, including the `flutter-base`
classifier, read `recoverable` from that edge catalog. There is no runtime
error-info API: clients never call Primordial, even during an error storm.

## Transformer and LocalError

`fromObject` folds any value into a `Problem` and never throws. A map whose
`problemId` the registry knows becomes that problem with the map's `data`;
anything else becomes the `uncatalogued` 5xx problem.

`LocalError(sink).wrap(error, stackTrace)` turns an unexpected client exception
into a `local_error` Problem with `message` and `stackTrace` in `data`, and
hands it to the `ErrorSink`. Rendering it is left to `flutter-base`.

## Conformance fixtures

`test/fixtures/c0/` pins an envelope with data, an envelope without data, a
type URI, a catalog entry and a full Problem CR. `manifest.json` maps each file
to its SHA-256 digest and is marked `local-regression-only`. The conformance
test recomputes each digest and rebuilds each fixture from the code, so an
altered fixture or a drifted implementation turns it red.

## TestHelper

```dart
import 'package:diene_problems/test_helper.dart';
```

- `expectProblem(actual, {type, title, status, recoverable, detail, instance,
data, noData})` checks only the fields given and throws
  `ProblemMatcherError` (an `AssertionError`) naming the first mismatch.
- `aProblem`, `anErrorPortal` and `aCatalogEntry` build valid values whose type
  URIs come from `problemTypeUri`. `aProblem()` is a valid `entity_not_found`;
  pass `data: null` for a data-less envelope.

The helper imports no test framework. Its meta suite proves each matcher fails
on known-bad and passes on known-good problems; meta coverage is a separate
ledger scoped to `lib/test_helper.dart`.
