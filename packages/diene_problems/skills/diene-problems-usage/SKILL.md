---
name: diene-problems-usage
description: Use when building, registering, cataloging or asserting RFC 9457 Problem envelopes in Dart with package:diene_problems, or exporting its Problem CR.
---

# diene_problems usage

The package doc (`doc/diene_problems.md`) is authoritative; read it first.

- Import only `package:diene_problems/diene_problems.dart`; never `lib/src`.
- Build every type URI with `problemTypeUri` (or a registry/catalog). Never
  format the URI string yourself.
- Wire ids are snake_case. Use `GenericProblems` for the baseline and declare
  domain problems as `ProblemType`s in the owning service.
- A problem without data passes `data: null`; it is omitted on the wire.
- Export the catalog with `ProblemCatalog.toProblemResource(version:)`, one per
  row. There is no runtime error-info API.
- Wrap unexpected client exceptions with `LocalError(sink).wrap(error, stack)`.

## Tests

Import `package:diene_problems/test_helper.dart`:

```dart
expectProblem(problem, type: registry.typeUriFor(GenericProblems.conflict),
    status: 409, data: {'entityType': 'note', 'id': '7'});
expectProblem(other, status: 401, noData: true);
final Problem fixture = aProblem(); // a valid entity_not_found
```

It throws `ProblemMatcherError` and adds no test framework to your graph.
