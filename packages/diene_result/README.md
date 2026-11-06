# diene_result

[![pub package](https://img.shields.io/pub/v/diene_result.svg)](https://pub.dev/packages/diene_result)
[![CI](https://github.com/ProtoDurian/diene.dart_result/actions/workflows/ci.yaml/badge.svg)](https://github.com/ProtoDurian/diene.dart_result/actions/workflows/ci.yaml)

Sealed `Result<T>` and `Option<T>` values for Dart, with a cross-language
tagged-array wire codec and a dependency-light test helper.

```dart
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

final Result<int> result = Result<int>.ok(21)
    .map((value) => value * 2)
    .andThen((value) => Result<int>.ok(value));

final String message = result.match(
  ok: (value) => 'answer: $value',
  err: (Problem problem) => problem.title,
);
```

The error channel is the RFC 9457 `Problem` from `diene_problems`; this package
depends on it and does not re-export it. `serial()` writes the tagged arrays:

- `['ok', value]` / `['err', problemJson]`
- `['some', value]` / `['none', null]`

`unwrap` and `unwrapErr` throw `UnwrapError` on the wrong variant; the
`unwrapOr` fallbacks avoid that. Callback exceptions propagate unless `exec`
maps them, and malformed wire input throws `FormatException`.

Unlike the Bun package, no server-side rendering (SSR) API ships here.

## TestHelper

Import `package:diene_result/test_helper.dart` in consumer tests for
`expectOk`, `expectErr`, `expectSome` and `expectNone`. They return the
unwrapped payload, throw `TestHelperFailure` on the wrong variant, and pull in
no test framework.

Read the [package doc](doc/diene_result.md) for the full API, the wire form,
the TestHelper and the differences from the Bun package.

## Development

- `task setup` resolves the workspace dependencies.
- `task test` runs the unit, conformance and TestHelper meta suites.
- `task test:coverage` enforces the separate unit and meta ledgers.
- `task deadcode` runs the repository and production-only dead-code passes.
- `task package:validate` runs the release guard, publish dry-run and pana.
