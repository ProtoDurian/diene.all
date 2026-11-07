# diene_api_engine test patterns

## Two backends, two tokens

```dart
final FakeHttpTransport transport = FakeHttpTransport.byHost({
  'users.example.test': okJson({'id': '1'}),
  'billing.example.test': problemResponse(problemFixture(status: 402)),
});
final FakeAuth auth = FakeAuth({
  'lithium/raichu/api/users': 'tok-users',
  'lithium/raichu/api/billing': 'tok-billing',
});
final ApiEngine engine =
    ApiEngine.fromConfig(config, auth: auth, transport: transport);
```

Assert on `transport.sent[i].headers['Authorization']` and `auth.queried` to
prove each call carried only its own backend's token.

## Response cases

- `okJson(body)` is a 2xx JSON object.
- `problemResponse(problem)` is a problem body at the problem's status.
- `nonProblemJson(body)` is JSON that is not a problem.
- `nonJsonResponse()` is a 502 text body.
- `networkFailure()` is no response at all.

Use `FakeHttpTransport.sequence([networkFailure(), okJson(...)])` to prove the
one retry, and `expectProblemType(result, BridgeProblems.transportFailure)` for
the failure cases.

## Rescue

Build a `RescueRouter` with `sleep: noSleep, jitter: noJitter` for fixed order,
`FakeClock().sleep` and `nowMs` to test budgets without waiting,
`HangingTransport` for a probe that never answers, and `FakeRescueStore` to
assert what was pinned.
