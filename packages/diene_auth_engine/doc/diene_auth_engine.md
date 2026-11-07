# diene_auth_engine guide

This package is the client half of authentication for Flutter apps. It has no
server guard and no fine-grained authorization: servers check ownership with
the nullable-user-id pattern, and the API host (the .NET API) mints and redeems
app-handoff tokens.

Every expected failure is a `Result` holding a `Problem`. A method that returns
a `Result` does not throw for an expected failure.

## Token lifecycle

- Access tokens live at most 10 minutes. Refresh tokens live at most 14 days
  and rotate on every use (`TokenLifetimes`).
- `SessionController` checks every token pair it receives. A pair that lives
  longer than these limits is rejected, not trusted.
- `refresh()` treats a changed refresh family, or the same refresh token handed
  back again, as reuse. It signs the session out and returns
  `urn:diene:problem:refresh-reuse`.
- `onAppOpen()` re-mints the access token every time the app opens and keeps
  the refresh token. An expired refresh token signs the session out.
- `AuthCoordinator` is the `IAuth` seam. It caches one token per `ResourceKey`,
  refreshes 30 seconds before expiry, and lets concurrent callers share one
  fetch. `fetchAllTokens` starts every key before awaiting any and returns one
  entry per distinct key.
- A `ResourceKey` is `(platform, landscape, service, resourceName)`. Its JWT
  audience is `https://<resourceName>.<service>.<platform>.<landscape>.cluster.atomi.cloud`.
- The Logto SDK rotates refresh tokens inside itself and never hands them out,
  so `LogtoAuthProvider` fills in the refresh fields of `SessionTokens` itself.

## Per-backend claims-first onboarding

One app can onboard to many backends. Each `RegisteredBackend` lists its
resources and the resource that guards its `/User` routes. There is no global
"onboarded" flag.

`MultiBackendOnboarding.runAll()` fetches one deduplicated token batch for all
backends, then runs one `OnboardingMachine` per backend. Each backend ends in
its own phase: `bootstrapping`, `needsOnboarding`, `ready` or `error`. Backend A
can be `ready` while backend B is `needsOnboarding` or `error`, and no token or
state crosses between them.

For each backend:

1. If every resource token carries the registration claim
   `<platform>_<service>` with the string value `"true"`, the backend is ready
   (or `needsOnboarding` when its own app onboarding claim is missing).
2. Otherwise call `GET /User/Me` once. On 404, `POST /User` with the ID token;
   2xx or 409 both count as done.
3. Refetch the backend's tokens and check the claim again. If it is still
   missing, the phase is `error` with `OnboardingClaimMissing`.

A later 401 or 404 on a backend whose claim was present is an ordinary error:
call `markStaleClaim()`. It never re-runs `/User/Me` or the create call. The
server's OnboardSync step writes the backend and home claims after a create.

## Deferred login

This package is only the mobile client of deferred login. The flow:

1. Read the carrier. On Android it is one `app_handoff` field in the Play Install
   Referrer; on iOS it is the clipboard text, trimmed. The text is
   `atomi-app-handoff:v1:<nonce>`, where the nonce is 43 unpadded base64url
   characters. Never log or store the nonce.
2. Mark the referrer processed, or clear the clipboard if it still holds the
   carrier, before redeeming.
3. `POST {mount}/redeem` with `{ nonce, device }`. The device fields are for
   telemetry only.
4. Pass the returned `one_time_token` and `login_hint` to
   `signIn(extraParams:)`. Normal onboarding then takes over.

The mount comes from `authEngine.appHandoffMount` and defaults to
`/app-handoff`. `redeemPath` is always `{mount}/redeem`; the client never adds
a second `app-handoff` segment. Every failure is the one 410 problem
`appHandoffExpired()`, which says nothing about the account, and the client
falls back to a normal login. There is no retry loop.

## Exact continuation

`ReturnTo` keeps the protected route the user asked for, path and query
exactly, across login. Only relative targets that start with a single `/` are
allowed; absolute URLs, `//host` and `/\` targets are refused as open
redirects. `buildLoginRedirect` adds the target, and `continueFrom` reads it
back with a fallback.

## Home landscape and Doc B

Every sign-in first reads the `home_landscape` claim from the JWT
(`HomeClaimResolver`).

- Claim present: use that landscape. Doc B is not fetched.
- Claim absent: fetch Doc B, ping each region, and pick. This happens on
  sign-in and on sign-up. If the flow is interrupted, the next sign-in fetches
  Doc B again, because the claim is still absent.

Doc B holds landscape names and metadata only, never an address or an issuer.
`LandscapeSelectorDoc.fromJson` rejects the whole document if it has any other
top-level key, a missing or non-string `platform` or `tier`, an entry without a
name, an address or issuer key at any depth, or any URL-like value. The
document URL must end in one of `endpointSuffixAllowlist` (default
`cluster.atomi.cloud`), or `HttpLandscapeSelectorSource` refuses to fetch it.

Ping URLs are built from each landscape name by a `PingUrlBuilder`; they never
come from the document. `HttpRegionPinger` waits 3 seconds by default. The
fastest healthy region wins, unless the caller's preferred region is healthy.
This is not a router: after selection the client uses one hostname.

`SignInCoordinator` runs the whole flow: read the home claim, sign in, read
the issued claim, onboard each backend, then confirm the home claim from a
fresh token. A Doc B pick is never stored as the home; only a confirmed claim
is. If `freshClaimToken()` cannot give a fresh token, it returns `null` and the
sign-in fails closed.

## Baked issuer

The OIDC issuer is build-time configuration (`authEngine.issuer`). It is never
taken from a document, and the Doc B parser refuses any `issuer` key.

## Config block schema

`AuthEngineConfig.blockSchema` is this engine's `authEngine` block schema. It
lives next to `AuthEngineConfig.fromBlock`, which reads the block. The
separate `config` package merges and validates the root schema that includes
it. There is no `standard-config` package for Dart.

## TestHelper

`package:diene_auth_engine/test_helper.dart` depends on no test framework. It
throws `AuthAssertionError` on a failed check.

- Fakes: `FakeAuthProvider`, `FakeAuth`, `FakeUserDirectory`,
  `FakeAppHandoffApi`, `FakeRedeemHttpClient`, `FakeLandscapeSelectorSource`,
  `FakeRegionPinger`, `MemoryHomeClaimStore`, `FakeInstallReferrerSource`,
  `FakeClipboardCarrierSource`.
- Builders: `AuthFixtures` (JWTs with or without the registration claim,
  session tokens, resource tokens, resource keys).
- Assertions: `AuthExpect` (`ok`, `err`, `errType`, `some`, `none`, `phase`,
  `status`).

## Parity with the Bun packages

### Doc B selector vs the Bun `frontend-utils` edge-document client

The Bun edge-document client handles all three edge documents (Doc A, Doc B,
Doc C), the problem catalog fetch and the dormant rescue router. Dart has no
`frontend-utils` package, so the work is split by owner:

| Concern                              | Dart owner                                        |
| ------------------------------------ | ------------------------------------------------- |
| Doc B fetch, ping and pick           | this package: `LandscapeSelectorClient`           |
| Suffix allowlist on the Doc B URL    | this package: `AuthEngineConfig.allowsUrl`        |
| Baked issuer, never from a document  | this package: required config key, parser refusal |
| Handing the home to the sign-in flow | this package: `HomeClaimResolver`                 |
| Doc A, Doc C and the rescue router   | `diene_api_engine`                                |
| Problem catalog shape                | `diene_problems`                                  |

Two differences matter:

- A bad URL rejects the whole Doc B document here, not one entry.
- This package does not track Doc B versions. Doc B is fetched only while the
  home claim is absent, so there is no earlier version to compare with.

### Other deliberate differences from the Bun auth engine

- Mobile client only: no mint or redeem server and no web-side handoff starter.
- No separate pre-onboarding phase: home resolution is the first step of
  `SignInCoordinator`, reported as `HomeResolutionKind`.
- One `IAuth` implementation, because a Flutter app has one runtime context.
- `Result<T>` always carries a `Problem` as its error.
- The fresh-claim read is an injected seam, because the Logto Dart SDK cannot
  force a token refresh.
- No client-side signature check: `Claims` only reads payloads.
- The package depends on the Flutter SDK, because `logto_dart_sdk` 3 needs it.
