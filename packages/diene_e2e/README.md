# diene_e2e

[![pub package](https://img.shields.io/pub/v/diene_e2e.svg)](https://pub.dev/packages/diene_e2e)

The test harness for the Diene Dart family. One dev dependency gives your
integration and end-to-end tests:

- the TestHelpers of `diene_result`, `diene_interfaces`, `diene_problems`,
  `diene_config`, `diene_auth_engine` and `diene_api_engine`, from one import;
- an in-process loopback `StubServer` to point your clients at;
- `Journey`, a small driver for named, ordered test steps;
- the app-handoff (deferred-login) fixture, `AppHandoffStub`, and a client
  driver, `DeferredLoginJourney`;
- plain-throw assertions that need no test framework.

```dart
import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';

final StubServer server = await StubServer.start();
final AppHandoffStub handoff =
    AppHandoffStub(problemTypeUri: 'https://api.example.com/AppHandoffExpired')
      ..addUser(const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com'))
      ..mintingUser = const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
handoff.mount(server);

final DeferredLoginJourney driver = DeferredLoginJourney(
  baseUrl: server.baseUrl,
  platform: 'android',
);
final DeferredLoginResult result = await driver.redeemCarrier(installReferrer);
// result.outcome is redeemed or interactiveFallback.
```

`package:diene_e2e/diene_e2e.dart` also re-exports the runtime API of all
seven family libraries, as 1.0.0 did.

Read the [package doc](doc/diene_e2e.md) for what is bundled, when to import a
member helper directly, how to drive journeys, the deferred-login driver, the
differences from the Bun harness and the known limits of 1.0.
