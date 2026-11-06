# Result and Option

`diene_result` ships sealed `Result<T>` and `Option<T>` values, synchronous
combinators, async extensions over `Future<Result<T>>`, and a tagged-array wire
codec shared with the other Diene language families. It depends on the hosted
`diene_problems` package, which owns the RFC 9457 `Problem` failure type.

## Result

Construct values with `Result.ok` and `Result.err` (or `Ok(...)` / `Err(...)`).
Transform only success with `map`, transform only failure with `mapErr`, chain
fallible work with `andThen`, and consume both variants with `match`. Test the
variant with `isOk` / `isErr`, project a channel with `ok()` / `err()`, and read
either payload with `native()`.

`unwrap` and `unwrapErr` throw `UnwrapError` (a `StateError` carrying the
monad, the expected and actual variant, and the payload) on the wrong variant;
`unwrapOr` and `unwrapOrElse` return a fallback instead. Callback exceptions
propagate through every combinator; `exec` alone turns one into an `Err`,
through the mapper the caller passes. Malformed wire input throws
`FormatException` (see below).

The error channel is always a `Problem` imported from
`package:diene_problems/diene_problems.dart`. This package neither defines nor
re-exports it; import `diene_problems` wherever code builds or names a failure.

## Async

`FutureResult` extends `Future<Result<T>>` with `map`, `mapErr`, `andThen` and
`match`, whose callbacks may return a value or a `Future`, plus `unwrap` and
`unwrapErr`.

## Option

Use `Option.some`, `Option.none` or `Option.fromNullable`. `map`, `andThen`,
`match`, `isSome` / `isNone`, `native()` and the unwrap family mirror Result.
`okOr` turns `Some` into `Ok` and `None` into `Err`; `asResult` maps both
variants into a `Result`; `errOr` on `Option<Problem>` turns `Some` into `Err`.

## Wire form

The JSON form is a two-item tagged array:

```text
Result: ["ok", value] | ["err", problemJson]
Option: ["some", value] | ["none", null]
```

`serial()` writes it; pass `encodeOk` / `encodeSome` to encode a payload that
is not already JSON. `Result.fromSerial` and `Option.fromSerial` need a payload
decoder and throw `FormatException` on an unknown tag, a wrong item count, a
`Problem` that is not an object or has a wrong member type, and a `None` with a
payload. An absent optional `Problem` member is omitted on the wire, never
written as `null`.

The test suite checks the codec against two fixture sets under
`test/fixtures/c0/`: the upstream cross-language vectors in `upstream/`, pinned
by commit and digest, and local regression fixtures pinned by `manifest.json`.
Changing a fixture byte fails the suite.

## TestHelper

Consumer tests may import `package:diene_result/test_helper.dart`:

- `expectOk(result)` returns the `Ok` value; `expectErr(result)` returns the
  `Problem`.
- `expectSome(option)` returns the `Some` value; `expectNone(option)` returns
  nothing.

On the wrong variant each throws `TestHelperFailure` naming the actual variant
and payload. The helper imports no test framework, so it adds nothing to a
consumer's production graph and works under any runner.

The meta suite in `test/meta/` shows each helper passing on a good value and
failing on a bad one. Its coverage ledger holds only `lib/test_helper.dart`,
which the unit ledger excludes.

## Differences from the Bun package

- Dart uses a sealed synchronous class hierarchy with async extensions on
  `Future<Result<T>>`; Bun's `@atomicloud/diene.result` is promise-backed.
- Dart fixes the error channel to `Problem` in a one-parameter `Result<T>`;
  Bun exposes `Result<T, E>`.
- No server-side rendering (SSR) API ships in Dart; the wire arrays are the
  same.
- Dart's `exec` needs an explicit exception-to-`Problem` mapper.
- Bun's heterogeneous `all` and error-collecting helpers have no single-`Problem`
  Dart equivalent and are left out.
- Dart uses `Result.ok` / `Result.err`, `Some` / `None` and lower-camel method
  names instead of TypeScript factory functions.
