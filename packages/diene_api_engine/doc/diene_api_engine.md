# diene_api_engine

The backend-client engine for Diene Flutter apps. Every call, raw or through a
generated OpenAPI SDK, returns `Result<T>` whose error is a `Problem`. Ordinary
failures never escape as exceptions.

```dart
import 'package:diene_api_engine/diene_api_engine.dart';
```

`Result`, `Ok`, `Err` (from `diene_result`), `Problem` (from `diene_problems`)
and `IAuth`, `ResourceKey`, `ResourceToken` (from `diene_auth_engine`) are
re-exported; this package never redefines them.

## Registering backends

One app registers many backends in one engine. Each backend is a
`BackendConfig`:

| field                 | meaning                                                       |
| --------------------- | ------------------------------------------------------------- |
| `coordinate`          | `LpsmCoordinate(landscape, platform, service, module)`        |
| `baseUrl`             | the one host this backend is called on                        |
| `resourceName`        | the auth resource for its token; null sends no token          |
| `timeout`             | carried in config (30 s default); the transport owns timeouts |
| `retryOnNetworkError` | retry once on a network failure (default true)                |

```dart
final ApiEngine engine = ApiEngine.fromConfig(
  ApiEngineConfig.fromMap(block), // the merged engine config block
  auth: authCoordinator,          // an IAuth from diene_auth_engine
  store: FileRescueStore(appDocumentsDir),
);
final Backend users = engine.backend(usersCoordinate)!;
```

- The coordinate key is `landscape.platform.service.module`. A duplicate
  coordinate is an `Err` from `ClientTree.register` and a `FormatException` from
  `ApiEngineConfig.fromMap`.
- `ApiEngine.fromConfig` uses `IoHttpTransport` unless you pass a `transport`.

## Per-backend auth

Before each call the backend asks `IAuth.tokenFor` for its own `ResourceKey`
(`platform`, `landscape`, `service`, `resourceName`) and sends
`Authorization: Bearer <token>`. Two backends never share a token. A token
failure is the call's `Err`; no HTTP request is sent.

The module slot is not part of the resource key. The key's labels must be valid
host labels (lowercase, no trailing hyphen); `ResourceKey` throws a
`FormatException` for a bad label when the backend first builds its key.

## Calling

Raw JSON call:

```dart
final Result<User> r = await users.call<User>(
  method: HttpMethod.get,
  path: '/users/42',
  decode: User.fromJson,
);
```

Generated SDK call: build the SDK on the backend, then wrap each call.

```dart
final ServiceSdk sdk = users.sdk(ServiceSdk.new);
final Result<UserProfile> r =
    await const ResultSdk().call(() => sdk.users.getUser(id: '42'));
```

`Backend.sdk` hands the generated client a Dio whose adapter
(`BackendClientAdapter`) sends every request through the same pipeline as
`call`: base URL or live pin, per-backend token, retry once, rescue.
`ResultSdk.call` turns a token failure into that `Problem`, any other Dio error
into the classification below, and any other throw into a transport failure.

The bundled `ServiceSdk` / `UsersClient` is a small generated sample (from
`openapi/service.openapi.yaml`, via swagger_parser and retrofit). It lives under
`lib/src/generated` and is not exported from the barrel; generate your own SDK
the same way.

## How a response becomes a Result

`toResult` reads what the response carries, not just its status:

| response                                                                 | result                                                         |
| ------------------------------------------------------------------------ | -------------------------------------------------------------- |
| 2xx with a JSON object                                                   | `Ok(decode(json))`                                             |
| any non-2xx (5xx too) whose body is a problem                            | that `Problem`, `data` included                                |
| non-2xx JSON object that is not a problem                                | unexpected response: status kept, body in `data.body`          |
| network failure, non-JSON body, status only, 2xx not JSON, failed decode | transport failure with status and a 256-character body snippet |

- "Is a problem" means a JSON object with a string `type` and an int `status`
  that `Problem.fromJson` accepts. A problem-shaped body it cannot parse (for
  example a numeric `title`) is an unexpected response.
- A JSON body that is not an object (an array, a number) is treated like a
  non-JSON body: a transport failure.
- The engine returns its own types `BridgeProblems.transportFailure`,
  `unexpectedResponse` and `duplicateBackend`, built by `diene_problems` under
  `BridgeProblems.portal` (local by default). `authTokenUnavailable` is defined
  for auth code to use; a token failure itself passes through unchanged.
  Missing optional members are omitted, never `null`.

## The hot path: one host, one retry

Each backend talks to exactly one host. `RetryOnceTransport` resends once when
no HTTP status came back (refused, reset, DNS, TLS, timeout). Any received
status, 5xx included, is returned at once. There is no list of physical URLs,
no circuit breaker and no failover ladder on the normal path.

## Rescue

Rescue is dormant. It runs only when all of these hold:

1. `rescue.enabled` is true for this app context (on for Flutter; a server
   context leaves it off and never builds a router);
2. a call got no HTTP status even after the one retry.

A received status of any kind never trips it.

### Steps

1. **Doc A.** Fetch `https://<host>/fleet.json` from each baked
   `rescue.catalogHosts` entry in order; the first allowed host that answers 200
   with `catalogHosts` and a numeric `version` wins. A Doc A older than the
   newest seen is a rollback and is refused.
2. **Doc C.** Fetch `https://<host>/catalog/<platform>.json` from each Doc A
   host. A Doc C is stored only when its `version` is newer than the one stored
   for this platform and landscape; otherwise the stored copy is used. Stored
   copies are kept forever.
3. **Scan.** Take the candidates for this backend's own
   `landscape.platform.service.module` key, in order. Before each probe wait a
   jitter in `[0, maxJitter]` (250 ms). Each probe is a `HEAD`; a status below
   500 is healthy. A probe gets at most `perCandidateTimeout` (3 s) and the
   whole scan at most `scanBudget` (8 s), jitter included; a probe that hangs
   or throws counts as unhealthy.
4. **Pin.** The first healthy candidate is pinned and saved as last-known-good,
   and the failed request is sent to it again, with the same one retry.
5. **Fallback.** If nothing is healthy in budget, the last-known-good address
   is used (not probed). If there is none, the call returns the transport
   failure.
6. **Heal.** While pinned, calls go to the pin. After a pinned call gets a
   status below 500, the primary is probed; when it is healthy the pin is
   cleared and the next call goes back to the primary.

### Safety rules

- Every URL from a document or from the store is checked against the baked
  `endpointSuffixAllowlist` when it is used: Doc A hosts, Doc C candidates, the
  pin and last-known-good. A URL that does not parse is skipped.
- Rescue changes addresses only, within the same landscape: candidates are
  looked up by a key that contains the landscape, so another landscape's
  address cannot be reached. Tokens and the request stay the same.
- The auth issuer (`rescue.issuer`, `RescueRouter.bakedIssuer`) is baked build
  config. No document can set it, and the engine never reads one from a
  document.
- The baked seeds (Cloudflare R2, S3 behind CloudFront, and the rescue-domain
  aliases) are the app's `rescue.catalogHosts` build config; the package bakes
  no hosts of its own.

### Storage

`RescueStore` is a string key/value seam. `FileRescueStore(dir)` writes one file
per key under `dir` (pass the app documents directory on Flutter);
`InMemoryRescueStore` is the default. Keys: `doca.version`,
`docc.<platform>.<landscape>`, `docc.version.<platform>.<landscape>`,
`pin.<coordinate>` and `lastgood.<coordinate>`.

## Engine-owned config block

The engine owns its block and exports its schema as
`ApiEngineConfig.schema` (`$id: urn:diene:config-block:api-engine`). The config
library merges and validates the composed root; it never owns this schema.
There is no `standard-config` package in the Dart family.

```yaml
backends:
  - coordinate: { landscape: raichu, platform: lithium, service: api, module: core }
    baseUrl: https://api.raichu.cluster.atomi.cloud
    resourceName: root # optional
    timeoutSeconds: 30 # optional
    retryOnNetworkError: true # optional
rescue:
  enabled: true
  issuer: https://api.lithium.aldehyde.raichu.cluster.atomi.cloud
  catalogHosts: [rescue-r2.example, rescue-cf.example]
  endpointSuffixAllowlist: [.cluster.atomi.cloud]
  scanBudgetMs: 8000 # optional
  perCandidateTimeoutMs: 3000 # optional
  maxJitterMs: 250 # optional
```

`ApiEngineConfig.fromMap` throws `FormatException` for a missing or wrong-typed
required key, an empty `backends` list or a duplicate coordinate.

## Differences from the Bun engine

- **Dart owns the whole rescue router.** Dart has no `frontend-utils` package,
  so Doc A, Doc C, the scan, pinning and the store live in this package. Bun
  splits its rescue machinery out into `frontend-utils`. Doc B (landscape
  picking) belongs to `diene_auth_engine` in Dart.
- Storage is `dart:io` files, not browser storage.
- The package needs the Flutter SDK, because `diene_auth_engine` does.
- No server-rendering surface.

## Known limits of 1.0

These are how 1.0 behaves today; each is a 2.0 candidate, not a promise.

- **Doc C shape.** The shared edge-doc rules describe Doc C as
  `{ platform, tier, version, catalog: { <landscape>: { <service>: { <module>: [...] } } } }`.
  1.0 reads `{ version, candidates: { "<landscape>.<platform>.<service>.<module>": [...] } }`.
- **Allowlist per entry.** The shared rules say one disallowed URL makes the
  whole document untrusted. 1.0 drops just that entry and uses the rest.
- **Doc A refresh.** Doc A is fetched only when rescue trips, not constantly,
  and its `ttl` is ignored.
- **Unexpected-response detail.** A non-problem JSON error keeps its body in
  `data.body`; `detail` is the fixed text `Non-problem JSON body`.
- **Coordinates are not validated** when the config is parsed; a bad label
  fails when the backend builds its resource key.
- `BackendConfig.timeout` is carried but not applied; the transport's own
  timeout (30 s for `IoHttpTransport`) applies.

## TestHelper

```dart
import 'package:diene_api_engine/test_helper.dart';
```

No test framework in its imports, so it adds nothing to a production graph.

- **Fake backends:** `FakeHttpTransport` (a responder function),
  `FakeHttpTransport.byHost` (one outcome per backend host) and
  `FakeHttpTransport.sequence` (outcomes in order, last repeats). Each records
  every request in `sent`. `HangingTransport` never answers.
- **Fake auth:** `FakeAuth({mapKey: token})` gives each `ResourceKey` its own
  token and an `Err` (401) for an unknown key; `queried` lists the keys asked
  for, so tests can prove no token crossed backends.
- **Fixtures:** `okJson`, `problemResponse`, `nonProblemJson`,
  `nonJsonResponse`, `networkFailure`, `problemFixture`.
- **Assertions:** `expectOk`, `expectErr`, `expectProblemType`, `check` throw
  `AssertionError` and return the value or problem on success.
- **Rescue:** `FakeRescueStore` (logs writes), `FakeClock`, `noSleep`,
  `noJitter`.

The package's meta tests run one behaviour suite against these fakes and
against a real loopback HTTP server, and require both to give the same results.
