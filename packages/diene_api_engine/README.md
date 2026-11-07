# diene_api_engine

[![pub package](https://img.shields.io/pub/v/diene_api_engine.svg)](https://pub.dev/packages/diene_api_engine)

The backend-client engine for Diene Flutter apps:

- wraps generated OpenAPI SDK calls and raw JSON calls into `Result<T>` with a
  `Problem` error, so ordinary failures never throw;
- registers many backends in one client tree, each with its own host and its
  own auth token (through `diene_auth_engine`'s `IAuth`);
- retries once on a network failure, with no failover on the normal path;
- runs a dormant, disk-cached rescue router that finds another address for the
  same backend in the same landscape after a hard failure;
- owns and exports its config block schema.

```dart
import 'package:diene_api_engine/diene_api_engine.dart';

final ApiEngine engine = ApiEngine.fromConfig(
  ApiEngineConfig.fromMap(block),
  auth: authCoordinator,
  store: FileRescueStore(appDocumentsDir),
);
final Backend users = engine.backend(usersCoordinate)!;

final Result<User> user = await users.call<User>(
  method: HttpMethod.get,
  path: '/users/42',
  decode: User.fromJson,
);

// MyServiceSdk is your own SDK, generated from your service's OpenAPI spec.
final MyServiceSdk sdk = users.sdk(MyServiceSdk.new);
final Result<Order> order =
    await const ResultSdk().call(() => sdk.orders.getOrder(id: '42'));
```

Tests can use `package:diene_api_engine/test_helper.dart`: fake backends, fake
per-backend auth, response fixtures and plain-throw assertions, with no test
framework dependency.

Read the [package doc](doc/diene_api_engine.md) for the full guide: response
classification, the rescue steps, the config block, differences from the Bun
engine and the known limits of 1.0.
