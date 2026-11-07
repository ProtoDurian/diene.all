---
name: diene-core-utils-usage
description: Use when consuming package:diene_core_utils in Dart — slugs and namespaced keys, layered config merges, environment coercion, loading config through a Vfs, or the ISO 8601 / RFC 3339 / IANA timezone wire forms.
---

# diene_core_utils usage

The package doc (`doc/diene_core_utils.md`) is authoritative; read it first.
`patterns.md` has short examples.

- Import `package:diene_core_utils/diene_core_utils.dart`; never `lib/src`.
  The shared temporal vectors are in `package:diene_core_utils/c0_temporal.dart`.
- Never hand-write a slug, a config merge or a date format; use the member here.
- Every fallible member returns `Result`; handle it with `match`, `andThen` or a
  `switch`, never `try`/`catch`.
- Instants on the wire are UTC with `Z`. `parseRfc3339Utc` rejects offsets;
  normalise offset input once with `normalizeRfc3339ToUtc`.
- Money and exact decimals stay strings: never pass them through
  `coerceEnvironmentScalar`.
- Config lists come only from indexed keys (`APP__TAGS__0`); a blank value is
  unset and never erases a lower layer.
- Take a `Vfs` parameter for file access and return its failures unchanged.

## TestHelper

There is none: test with `InMemoryVfs` from
`package:diene_interfaces/test_helper.dart`. If a real consumer need appears
(a fake or an assertion every consumer repeats), add `lib/test_helper.dart` to
this package with no test-framework import, cover it under `test/meta/`, and
the meta test tier and its coverage ledger switch on by themselves.
