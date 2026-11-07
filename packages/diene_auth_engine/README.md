# diene_auth_engine

[![pub package](https://img.shields.io/pub/v/diene_auth_engine.svg)](https://pub.dev/packages/diene_auth_engine)
[![CI](https://github.com/ProtoDurian/diene.dart_auth_engine/actions/workflows/ci.yaml/badge.svg)](https://github.com/ProtoDurian/diene.dart_auth_engine/actions/workflows/ci.yaml)

The client-side auth engine for Flutter apps. It runs Logto sign-in, keeps
the token lifecycle, gets an access token per resource, onboards the user to
each backend on its own, redeems a deferred-login carrier, resumes the exact
protected route after login, and picks the home landscape from Doc B.

Every expected failure comes back as a `Result` holding an RFC 9457 `Problem`
from `package:diene_result` and `package:diene_problems`. JWT claims decide
everything: `GET /User/Me` is only called while a registration claim is absent.

```dart
import 'package:diene_auth_engine/diene_auth_engine.dart';

final AuthEngineConfig config = AuthEngineConfig.fromBlock(block['authEngine']!);

final ResourceKey api = ResourceKey(
  platform: 'lithium',
  landscape: 'lapras',
  service: 'api',
  resourceName: 'root',
);

final LogtoAuthProvider provider = LogtoAuthProvider(
  config: config,
  primaryResource: api,
);
final IAuth auth = AuthCoordinator(provider: provider);
final SessionController session = SessionController(provider: provider);
```

In tests, use the shipped fakes; no mocking framework is needed:

```dart
import 'package:diene_auth_engine/test_helper.dart';

final FakeAuthProvider provider = FakeAuthProvider(
  onSignIn: () => AuthFixtures.sessionTokens(now: DateTime.utc(2026, 11, 7)),
);
final SessionTokens tokens = AuthExpect.ok(
  await SessionController(provider: provider).signIn(),
);
```

## What it covers

| Area               | Main types                                                                            |
| ------------------ | ------------------------------------------------------------------------------------- |
| Sign-in and tokens | `AuthProvider`, `LogtoAuthProvider`, `SessionController`, `TokenLifetimes`            |
| Per-resource token | `ResourceKey`, `IAuth`, `AuthCoordinator`, `ResourceToken`                            |
| Onboarding         | `RegisteredBackend`, `BackendRegistry`, `OnboardingMachine`, `MultiBackendOnboarding` |
| Claims             | `Claims`                                                                              |
| Deferred login     | `AppHandoffCarrier`, `DeferredLoginClient`, `HttpAppHandoffApi`                       |
| Home landscape     | `HomeClaimResolver`, `LandscapeSelectorClient`, `HttpLandscapeSelectorSource`         |
| Continuation       | `ReturnTo`, `SignInCoordinator`                                                       |
| Config block       | `AuthEngineConfig`, `AppHandoffConstants`                                             |

The full guide, including how this package compares with the Bun
`frontend-utils` edge-document client, is in
[`doc/diene_auth_engine.md`](doc/diene_auth_engine.md).

## Flutter

This package needs the Flutter SDK: `logto_dart_sdk` 3 is a Flutter package and
the iOS clipboard reader uses `package:flutter/services.dart`. Run its tests
with `flutter test`.

## License

MIT.
