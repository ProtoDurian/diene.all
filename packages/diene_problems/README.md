# diene_problems

[![pub package](https://img.shields.io/pub/v/diene_problems.svg)](https://pub.dev/packages/diene_problems)
[![CI](https://github.com/ProtoDurian/diene.dart_problems/actions/workflows/ci.yaml/badge.svg)](https://github.com/ProtoDurian/diene.dart_problems/actions/workflows/ci.yaml)

RFC 9457 problem details for Dart: the envelope with the `data` and
`recoverable` extensions, the one type-URI builder, a typed registry with the
generic baseline, `LocalError` wrapping, and the Problem catalog export that
the edge error portal publishes. It has no runtime dependencies and no runtime
error-info API.

```dart
import 'package:diene_problems/diene_problems.dart';

const ErrorPortal portal = ErrorPortal(
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
);

// https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/entity_not_found
final String type = problemTypeUri(
  portal: portal,
  version: 'v1',
  id: 'entity_not_found',
);

final ProblemCatalog catalog = ProblemCatalog(portal: portal)..addGenerics();
final Map<String, Object?> cr = catalog.toProblemResource(version: 'v1');
```

## Public surface

- `Problem` — the envelope; `data` is omitted on the wire when absent.
- `problemTypeUri` / `ErrorPortal` — the only type-URI builder.
- `ProblemType` / `ProblemRegistry` / `GenericProblems` — versioned
  declarations and the generic baseline.
- `CatalogEntry` / `CatalogEndpoint` / `ProblemCatalog` — per-endpoint catalog
  entries and the Problem CR for one row.
- `fromObject` / `TransformOptions` — fold any value into a `Problem`.
- `LocalError` / `ErrorSink` — wrap unexpected client exceptions.

## TestHelper

Consumer tests may import `package:diene_problems/test_helper.dart` for
`expectProblem` (a plain-throw matcher) and the `aProblem`, `anErrorPortal` and
`aCatalogEntry` builders. It pulls in no test framework.

Read the [package doc](doc/diene_problems.md) for the full contract.

## Development

- `task setup` resolves the workspace dependencies.
- `task test` runs the unit, conformance and TestHelper meta suites.
- `task test:coverage` enforces the separate unit and meta ledgers.
- `task deadcode` runs the repository and production-only dead-code passes.
- `task package:validate` runs the release guard, publish dry-run and pana.
