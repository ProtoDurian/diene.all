# diene_dart_lib

[![pub package](https://img.shields.io/pub/v/diene_dart_lib.svg)](https://pub.dev/packages/diene_dart_lib)
[![CI](https://github.com/ProtoDurian/diene.dart_lib/actions/workflows/ci.yaml/badge.svg)](https://github.com/ProtoDurian/diene.dart_lib/actions/workflows/ci.yaml)

The generic, pure-Dart **library template** for the Diene family. It ships a
small, replaceable sample domain — a `Note` value type with a JSON wire codec
and a pure summariser — inside the reusable template machinery (strict analysis,
targeted coverage, a dependency-light TestHelper, a C0 fixture harness, package
hygiene, and a shipped usage skill).

```dart
import 'package:diene_dart_lib/diene_dart_lib.dart';

const Note note = Note(title: 'Release', body: 'Ship the template.');

final String summary = summarizeNote(note);        // 'Release — Ship the template.'
final Note decoded = Note.fromJson(note.toJson());  // round-trips through JSON
```

## Public surface

- `Note` — immutable `title`/`body` value type with value equality and a JSON
  wire codec (`Note.fromJson` / `toJson`).
- `summarizeNote(note, {maxLength})` — a pure single-line summariser.
- `defaultSummaryLength` — the default summary cap.

## TestHelper

Consumer tests may import `package:diene_dart_lib/test_helper.dart` for
`assertNoteSummary`, a dependency-light assertion that throws
`NoteAssertionFailure` on mismatch and pulls in no test framework.

Read the [package doc](doc/diene_dart_lib.md) for the full API, wire contract,
C0 harness, and guidance on replacing the sample.

## Using this template

This is a template: a materialized child retokenizes the package identity to
`diene_<name>` / `ProtoDurian/diene.dart_<name>`, replaces `lib/src/**` with its
own domain, and re-points the barrel exports. See
`skills/diene-dart-lib-usage/patterns.md`.

## Development

- `task setup` resolves the workspace dependencies.
- `task test` runs the unit, C0 conformance, TestHelper meta, and consumer tiers.
- `task test:consumer` packs the package with pub, installs that local archive
  in a fresh project, then imports, runs, compiles and type-checks it.
- `task test:coverage` enforces the separate unit and meta ledgers.
- `task deadcode` runs the repository and production-only dead-code passes.
- `task package:validate` runs the release guard, publish dry-run, and pana.
