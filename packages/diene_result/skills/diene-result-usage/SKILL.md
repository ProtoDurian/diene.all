---
name: diene-result-usage
description: Use when Dart code handles fallible or optional values with package:diene_result — Result, Option, their wire codec, or the expectOk/expectErr/expectSome/expectNone test helpers.
---

# diene_result usage

Import `package:diene_result/diene_result.dart`, and
`package:diene_problems/diene_problems.dart` wherever code builds or names a
`Problem`; never import `lib/src`.

Use `map`, `mapErr`, `andThen` and `match` for control flow; keep `unwrap` for
invariants already proved. Use `serial()` / `fromSerial()` only at a JSON
boundary.

In tests, import `package:diene_result/test_helper.dart` for `expectOk`,
`expectErr`, `expectSome` and `expectNone`.

The full API, wire form and TestHelper are in `doc/diene_result.md`; patterns
are in `patterns.md`.
