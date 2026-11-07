# diene_e2e

`diene_e2e` is the family test harness for Diene Flutter apps. It is glue: it
bundles the member TestHelpers and adds the wiring that integration and
end-to-end tests would otherwise repeat. Engine behaviour stays in the engines.

## Two imports

| Import                               | What it gives you                                                                                         |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `package:diene_e2e/test_helper.dart` | The six member TestHelpers, `StubServer`, `Journey`, `AppHandoffStub`, `DeferredLoginJourney`, assertions |
| `package:diene_e2e/diene_e2e.dart`   | The runtime API of all seven family libraries, plus the app-handoff carrier codec and wire models         |

The TestHelper import has no test framework in it (no `test`, `matcher` or
mocking package). Its assertions throw `JourneyAssertionError`, so they work
under any runner.

## What is bundled

| Member              | Runtime API | TestHelper passthrough                                       |
| ------------------- | ----------- | ------------------------------------------------------------ |
| `diene_result`      | yes         | yes                                                          |
| `diene_interfaces`  | yes         | yes                                                          |
| `diene_problems`    | yes         | yes                                                          |
| `diene_config`      | yes         | yes                                                          |
| `diene_auth_engine` | yes         | yes                                                          |
| `diene_api_engine`  | yes         | yes, without `FakeAuth`, `expectOk`, `expectErr`             |
| `diene_core_utils`  | yes         | no: it ships no TestHelper (pure functions, nothing to fake) |

Two names are declared by two members. The bundle keeps the owner's:

- `expectOk` and `expectErr` come from `diene_result`, which owns `Result`.
  They throw `TestHelperFailure`.
- `FakeAuth` comes from `diene_auth_engine`, which owns `IAuth`. It takes
  batches of token maps and counts fetches.

## When to import a member helper directly

- You want the `diene_api_engine` variants: its `FakeAuth` (one flat map of
  token strings
  that records which keys were asked for) or its `expectOk`/`expectErr` with a
  `because:` label. Import it with a prefix:

  ```dart
  import 'package:diene_api_engine/test_helper.dart' as api;

  final api.FakeAuth auth = api.FakeAuth(<String, String>{'users': 'token'});
  ```

- The test touches one member only. Depend on that member and its TestHelper;
  you do not need the whole harness.

Member fakes and assertions are documented in each member's own doc and skill.

## Driving journeys

1. Start a server: `final StubServer server = await StubServer.start();`
2. Register routes: `server.on('GET', '/health', (StubRequest r) =>
StubResponse.json(<String, Object?>{'ok': true}));` A request with no route
   gets 404. `StubResponse.json` sets `Content-Type: application/json` and
   `Cache-Control: no-store`.
3. Point the client under test at `server.baseUrl`.
4. Write the flow as a `Journey` of named `JourneyStep`s. `run()` stops at the
   first step that returns `false` or throws.
5. Assert with `expectJourneyOk(result)` or
   `expectJourneyFailedAt(result, 'step name')`, and check what the client sent
   in `server.requests`.
6. `await server.close()` in tear-down.

`server.handlerFor(method, path)` returns a registered handler so you can call
it directly. Use it to test what a handler throws (see Known limits).

## The deferred-login (app-handoff) fixture

`AppHandoffStub` is the Dart host for the shared app-handoff contract. Mount it
on your `StubServer`:

- `POST {mount}` mints a nonce for `mintingUser` (set it first; the stub throws
  a `StateError` without it). The default mount is `/app-handoff`.
- `POST {mount}/redeem` redeems it: `200 {token, email, expiresIn: 120}`.
- A nonce works once and lives 15 minutes. Pass `now:` to `mount` to control
  the clock.
- Every failure gets the same `410` `AppHandoffExpired` body: unknown, expired
  or replayed nonce; deleted or suspended user; an email that changed since the
  mint; a body that is not JSON, has an unknown key or a bad device field. A
  bad body never uses up the nonce.

Drive the client half with `DeferredLoginJourney`:

- `redeemCarrier(raw)` reads an Install Referrer (`platform: 'android'`) or
  clipboard text (any other platform), then redeems.
- `redeemNonce(nonce)` redeems a nonce you already have.
- Any carrier problem or non-200 answer gives `interactiveFallback`; no request
  is sent for a carrier that does not parse.

To test the production client itself, run `diene_auth_engine`'s
`DeferredLoginClient` with `HttpAppHandoffApi` against the same stub. The
package's conformance tests do exactly that.

The conformance tests check the stub, the driver and the carrier codec against
the shared app-handoff vectors.

## Boundaries: no OpenTelemetry, no standard-config

The Dart family has no OpenTelemetry library and no `standard-config` library,
so this harness has no passthrough or helper for either, and none should be
added to mimic Bun. Telemetry fakes and config fakes come only from the members
that exist (`diene_config` for config).

## Differences from the Bun harness

- **Eight Dart packages:** seven libraries (`diene_result`,
  `diene_interfaces`, `diene_problems`, `diene_core_utils`, `diene_config`,
  `diene_auth_engine`, `diene_api_engine`) plus this harness.
- **No OpenTelemetry and no `standard-config` member**, as above.
- **Dart libraries instead of subpath exports:** one runtime import and one
  TestHelper import.
- **Production re-export and version train: open.** 1.0.0 re-exports every
  member's runtime API from `diene_e2e.dart`, and this release keeps that. It
  is not decided whether `diene_e2e` should act as a coordinated version train
  the way the Bun harness does; do not rely on it moving members in lockstep.
  Each member keeps its own version, and this package depends on caret ranges
  of the published releases.

## Known limits of 1.0

These are kept for 1.0 compatibility and are candidates for 2.0.

- **Carrier codec overlap.** `diene_auth_engine` owns the carrier format
  (`AppHandoffCarrier`). Here `isValidAppHandoffNonce`,
  `buildAppHandoffCarrier` and `parseAppHandoffCarrier` use it, but
  `parseAppHandoffInstallReferrer` and `parseAppHandoffClipboard` keep their
  1.0.0 rules, which differ from the auth engine's in three ways:
  - a percent-encoded field name such as `app%5Fhandoff` counts as
    `app_handoff` here, not in the auth engine;
  - a bare `app_handoff` with no `=` counts as a field here (so with a real
    field it is a duplicate and the carrier is absent); the auth engine skips
    it;
  - the clipboard trims only ASCII space, tab, CR and LF here; the auth engine
    also trims other whitespace (for example a no-break space).
- **Wire model overlap.** `AppHandoffDevice`, `AppHandoffRedeemResponse` and
  `AppHandoffExpired` repeat the auth engine's `DeviceInfo`, `RedeemResult` and
  `appHandoffExpired()`. The auth engine's problem has a fixed `type`; here the
  `type` is passed in.
- **The driver repeats the client flow.** `DeferredLoginJourney` does not mark
  the referrer processed or clear the clipboard, as `DeferredLoginClient` does.
- **A throwing handler stops the server.** A `StubServer` handler that throws
  (including the mint route without `mintingUser`) never answers that request;
  the error escapes as an uncaught async error and the server stops serving.
- **The driver can throw.** `redeemNonce` throws on a network failure, or on a
  `200` whose body is not a redeem JSON object.
- **Members are built from their 1.0 releases.** Building against releases of
  the members published from their next climbs is not done yet.

## Release

The version in `pubspec.yaml` is `0.0.0` in source and is stamped only by the
release workflow.
