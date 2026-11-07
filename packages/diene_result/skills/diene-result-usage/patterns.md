# diene_result patterns

## Keep failures explicit

Use `map`, `mapErr`, `andThen` and `match` for routine control flow. Reserve
`unwrap` and `unwrapErr` for invariants already proved at the call site. The
ordinary combinators let callback exceptions propagate; `exec` is the explicit
boundary that turns a thrown object and stack trace into a `Problem`.

## Encode only at boundaries

Keep `Result<T>` and `Option<T>` inside application code. Call `serial()` and
`fromSerial()` only at a JSON boundary, with a decoder for the `Ok` or `Some`
payload.

## Assert with the TestHelper

Prefer `final int value = expectOk(result);` over unwrapping by hand: a wrong
variant fails with the actual variant and payload in the message. Use
`expectErr` to get the `Problem` and assert on its members.
