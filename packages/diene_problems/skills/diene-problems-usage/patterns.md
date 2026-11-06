# diene_problems patterns

## Declare a domain problem

```dart
const ProblemType noteLocked = ProblemType(
  id: 'note_locked',
  title: 'Note locked',
  version: 'v1',
  status: 423,
  recoverable: true,
  dataSchema: {
    'type': 'object',
    'properties': {'noteId': {'type': 'string'}},
    'required': ['noteId'],
    'additionalProperties': false,
  },
);
```

Leave `dataSchema` out for a problem without data; the catalog then publishes
`{"not":{}}` and the envelope omits `data`.

## Export the Problem CR

```dart
final ProblemCatalog catalog = ProblemCatalog(portal: portal)
  ..addGenerics()
  ..addType(noteLocked, endpoints: const [
    CatalogEndpoint(method: 'PUT', path: '/notes/{id}'),
  ]);
final Map<String, Object?> cr = catalog.toProblemResource(version: 'v1');
```

Emit one CR per version. Every entry must belong to that row, or
`ProblemResourceError` is thrown.

## Assert in tests

Prefer `expectProblem` over hand-written field checks; it names the first
mismatched field. Build inputs with `aProblem`, `anErrorPortal` and
`aCatalogEntry` so test URIs come from the same builder as production.
