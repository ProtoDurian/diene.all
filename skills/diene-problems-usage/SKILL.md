---
name: diene-problems-usage
description: Use when registering, emitting, transforming, or asserting RFC 9457 Problems with @atomicloud/diene.problems, including the six generic problems and the expectProblem TestHelper.
---

# Diene Problems usage

The rules and copy-ready snippets are in [patterns.md](patterns.md); read it
before changing a Problem contract.

- Build one `ProblemRegistry` from the configured `ErrorPortalConfig`. Never
  format a type URI by hand; the registry builds it.
- Get the six generics (`validation_error`, `entity_not_found`, `conflict`,
  `unauthenticated`, `unauthorized`, `invalid_json`) from
  `new GenericProblemCatalog().createGenericProblemRegistry(portal, version)`.
  Register domain problems in your service, never in this package.
- Bump `version` to change a published problem; a new version is a new type.
- Declare endpoints with `ProblemCatalog.declare`, then emit the primordial
  chart row with `ProblemResourceEmitter.emitProblemResource`.
- Map unknown errors with `ProblemTransformer`; HTTP-to-`Result` bridging lives
  in `@atomicloud/diene.api-engine`.
- In tests, use `ProblemTestHelper` from
  `@atomicloud/diene.problems/test-helper`:
  `helper.expectProblem(actual).toBe(entry, { data })`.
