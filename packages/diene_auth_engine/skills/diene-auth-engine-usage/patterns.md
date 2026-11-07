# diene_auth_engine patterns

## Two backends with independent phases

```dart
final MultiBackendOnboarding onboarding = MultiBackendOnboarding(
  registry: BackendRegistry(<RegisteredBackend>[billing, chat]),
  auth: auth,
  directory: directory,
  idToken: provider.idToken,
);
final Map<String, Result<OnboardingPhase>> phases = await onboarding.runAll();
```

## Deferred login at a custom mount

```dart
final AuthEngineConfig config = AuthEngineConfig.fromBlock(<String, Object?>{
  ...block,
  'appHandoffMount': '/auth/handoff',
});
final DeferredLoginClient client = DeferredLoginClient(
  api: HttpAppHandoffApi(base: apiBase, redeemPath: config.redeemPath),
  device: const DeviceInfo(platform: 'ios'),
  clipboard: const ClipboardCarrierReader(),
);
final DeferredLoginOutcome outcome = await client.prepare();
if (outcome is DeferredLoginReady) {
  await session.signIn(extraParams: outcome.extraParams);
}
```

## Testing redeem against the stub

```dart
final FakeRedeemHttpClient server = FakeRedeemHttpClient(mount: '/auth/handoff');
final HttpAppHandoffApi api = HttpAppHandoffApi(
  base: Uri.parse('https://api.example.test'),
  redeemPath: config.redeemPath,
  client: server,
);
final RedeemResult redeemed = AuthExpect.ok(
  await api.redeem(nonce: 'A' * 43, device: const DeviceInfo(platform: 'ios')),
);
// server.requests.single.path == '/auth/handoff/redeem'
```

## Testing a backend that must create its user

```dart
final ResourceKey key = AuthFixtures.resourceKey();
final FakeAuth auth = FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
  {key: Ok(AuthFixtures.resourceToken(now: now, jwtToken: AuthFixtures.unregisteredJwt(key)))},
  {key: Ok(AuthFixtures.resourceToken(now: now, jwtToken: AuthFixtures.registeredJwt(key)))},
]);
final FakeUserDirectory directory = FakeUserDirectory(getStatus: 404);
// run the machine, then:
AuthExpect.phase(machine.phase, OnboardingPhase.ready);
// directory.postCount == 1
```
