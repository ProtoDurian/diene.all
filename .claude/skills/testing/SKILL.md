---
name: testing
description: Use when choosing or implementing unit, functional, integration, SIT, or E2E tests.
---

Read [the testing standard](../../../docs/standards/testing/index.md) before editing this surface.

## TypeScript

Mark every test body `// Arrange`, `// Act`, `// Assert`. Assert in prototype
form; `should(value)` only for `null` or `undefined` (full table in the
standard's `languages/typescript.md`):

| Check            | Write                                                                            |
| ---------------- | -------------------------------------------------------------------------------- |
| equality         | `actual.should.equal(expected)`, `actual.should.deepEqual(expected)`             |
| boolean          | `result.should.be.true()`                                                        |
| defined          | `value.should.not.be.undefined()`                                                |
| null / undefined | `should(value).be.null()`, `should(value).be.undefined()`                        |
| throws / rejects | `act.should.throw(ErrorType)`, `await promise.should.be.rejectedWith(ErrorType)` |
