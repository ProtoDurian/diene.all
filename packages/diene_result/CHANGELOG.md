# Changelog

All notable changes to this package are documented here. Releases are managed
from conventional commits by the repository release workflow.

## Unreleased (0.0.0)

No public symbol or signature changes from 1.0.0.

Changed:

- The package moves to the `ProtoDurian/diene.dart_result` repository.
- The test suite checks the wire codec against pinned copies of the upstream
  cross-language vectors and local regression fixtures, instead of a generated
  projection of a fixture release. Nothing shipped changes.

## 1.0.0

- Add sealed Result and Option capability sets.
- Add C0-compatible Result and Option wire codecs projected from the frozen
  `c0-fixtures-r2` release.
- Add dependency-light consumer assertions and their meta tier.
- Use the sole `Problem` identity owned by `diene_problems`.
