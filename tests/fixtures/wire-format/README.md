# Wire-format fixtures

`tests/unit/problem/wire_format_test.go` loads these files and checks the library
against them:

- `envelope.json`: RFC 9457 members, the `data` and `recoverable` extensions, a
  sample with data and a sample without data (no `data` member on the wire).
- `catalog-entry.json`: the Problem resource `problems[]` entry keys and a sample.
- `type-uri.json`: the type-URI template, its segments and the expected URI.

They are written by hand from the shared cross-language contract. Change the
fixture, not the test, when that contract changes.
