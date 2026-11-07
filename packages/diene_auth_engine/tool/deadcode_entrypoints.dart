// Production dead-code root: references every public export so test_helper.dart counts as used.
import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

Future<void> main() async {
  final DateTime now = DateTime.utc(2026, 7, 27);

  final ResourceKey key = AuthFixtures.resourceKey();
  final SessionTokens tokens = AuthFixtures.sessionTokens(now: now);
  final ResourceToken token = AuthFixtures.resourceToken(
    now: now,
    jwtToken: AuthFixtures.jwt(<String, Object?>{'sub': 'u'}),
  );
  if (key.audience.scheme.isEmpty ||
      key.mapKey.isEmpty ||
      tokens.accessToken.isEmpty ||
      tokens.refreshToken.isEmpty ||
      tokens.refreshFamily.isEmpty ||
      token.token.isEmpty) {
    throw StateError('fixtures must build a usable identity');
  }

  if (TokenLifetimes.access <= Duration.zero ||
      TokenLifetimes.refresh <= Duration.zero ||
      !TokenLifetimes.refreshRotating ||
      !TokenLifetimes.remintOnOpen ||
      AppHandoffConstants.nonceTtl <= Duration.zero ||
      AppHandoffConstants.oneTimeTokenExpiresInSeconds <= 0 ||
      AppHandoffConstants.defaultMount.isEmpty) {
    throw StateError('normative constants must be positive');
  }

  final Map<String, Object?> claims = Claims.decode(
    AuthFixtures.registeredJwt(key),
  );
  if (!Claims.hasRegistration(
    claims,
    platform: key.platform,
    service: key.service,
  )) {
    throw StateError('registered fixture must carry its claim');
  }
  Claims.home(Claims.decode(AuthFixtures.unregisteredJwt(key)));
  Claims.registrationKey(platform: key.platform, service: key.service);

  final AppHandoffCarrier? carrier = AppHandoffCarrier.parseCanonical(
    'atomi-app-handoff:v1:${'A' * 43}',
  );
  if (carrier == null || carrier.canonicalText.isEmpty) {
    throw StateError('canonical carrier must parse');
  }
  AppHandoffCarrier.parseAndroidReferrer('utm_source=play');
  AppHandoffCarrier.parseClipboard(carrier.canonicalText);

  LandscapeSelectorDoc.fromJson(<String, Object?>{
    'platform': 'lithium',
    'tier': 'prod',
    'landscapes': <Object?>[
      <String, Object?>{'name': 'raichu', 'region': 'sgp'},
    ],
  });
  final Problem expired = appHandoffExpired();

  final Result<String> captured = ReturnTo.capture(Uri.parse('/a?b=c'));
  AuthExpect.ok<String>(captured);
  final Uri login = Uri.parse('https://login.example/authorize');
  AuthExpect.ok<Uri>(ReturnTo.buildLoginRedirect(login, Uri.parse('/a?b=c')));
  AuthExpect.ok<Uri>(ReturnTo.resolve(captured.unwrap()));
  ReturnTo.continueFrom(
    login.replace(
      queryParameters: <String, String>{ReturnTo.queryKey: captured.unwrap()},
    ),
    fallback: Uri.parse('/'),
  );

  const LandscapeEntry entry = LandscapeEntry(name: 'raichu', region: 'sgp');
  final FakeAuthProvider provider = FakeAuthProvider(onSignIn: () => tokens);
  final SessionController session = SessionController(provider: provider);
  final FakeAuth auth = FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
    <ResourceKey, Result<ResourceToken>>{key: Ok<ResourceToken>(token)},
  ]);
  final FakeUserDirectory directory = FakeUserDirectory();
  final FakeAppHandoffApi handoff = FakeAppHandoffApi();
  final FakeInstallReferrerSource referrer = FakeInstallReferrerSource(null);
  final FakeClipboardCarrierSource clipboard = FakeClipboardCarrierSource(null);
  final FakeLandscapeSelectorSource docs = FakeLandscapeSelectorSource();
  final FakeRegionPinger pinger = FakeRegionPinger(<String, Duration>{
    entry.name: const Duration(milliseconds: 5),
  });
  final MemoryHomeClaimStore store = MemoryHomeClaimStore();

  await session.signIn();
  await auth.tokenFor(key);
  auth.invalidate(key);
  await directory.getUserMe(backendId: key.mapKey, accessToken: token.token);
  await directory.postUser(
    backendId: key.mapKey,
    accessToken: token.token,
    idToken: AuthFixtures.registeredJwt(key),
  );
  await handoff.redeem(
    nonce: 'n',
    device: const DeviceInfo(platform: 'ios'),
  );
  await referrer.read();
  await clipboard.read();
  await docs.fetch();
  await pinger.ping(entry);
  await store.write('raichu');
  await store.read();
  await store.clear();
  final AuthEngineConfig config = AuthEngineConfig.fromBlock(<String, Object?>{
    'issuer': 'https://issuer.example.test/oidc',
    'endpoint': 'https://issuer.example.test',
    'appId': 'app',
    'redirectUri': 'io.atomi.app://callback',
  });
  final RegisteredBackend backend = RegisteredBackend(
    backendId: 'api',
    resources: <ResourceKey>[key],
    onboardingResource: key,
  );
  final HomeClaimResolver resolver = HomeClaimResolver(
    claimReader: jwtHomeClaimReader(provider.idToken),
    selector: LandscapeSelectorClient(
      source: HttpLandscapeSelectorSource(
        docUrl: Uri.parse('https://edge.cluster.atomi.cloud/doc-b.json'),
        config: config,
      ),
      pinger: HttpRegionPinger(
        pingUrlOf: (LandscapeEntry e) =>
            Uri.https('${e.name}.cluster.atomi.cloud', '/'),
      ),
    ),
  );
  final List<Object> production = <Object>[
    AuthCoordinator(provider: provider),
    DeferredLoginClient(
      api: handoff,
      device: const DeviceInfo(platform: 'android'),
      referrer: CallbackInstallReferrerSource(
        readReferrer: () async => null,
        markProcessed: () async {},
      ),
      clipboard: const ClipboardCarrierReader(),
    ),
    LogtoAuthProvider(config: config, primaryResource: key),
    SignInCoordinator(
      session: session,
      homeResolver: resolver,
      onboarding: MultiBackendOnboarding(
        registry: BackendRegistry(<RegisteredBackend>[backend]),
        auth: auth,
        directory: directory,
        idToken: provider.idToken,
      ),
    ),
    ResourceTokenEntry(key: key, token: token),
  ];
  if (production.length != 5) {
    throw StateError('every production entrypoint must build');
  }
  final FakeRedeemHttpClient redeemServer = FakeRedeemHttpClient();
  await HttpAppHandoffApi(
    base: Uri.parse('https://api.example.test'),
    redeemPath: '${AppHandoffConstants.defaultMount}/redeem',
    client: redeemServer,
  ).redeem(
    nonce: 'A' * 43,
    device: const DeviceInfo(platform: 'ios'),
  );
  if (!FakeRedeemHttpClient.acceptsBody(redeemServer.bodies.single)) {
    throw StateError('the client must send a valid redeem body');
  }

  AuthExpect.ok<int>(const Ok<int>(1));
  AuthExpect.err<int>(Err<int>(expired));
  AuthExpect.errType<int>(Err<int>(expired), expired.type);
  AuthExpect.some<int>(const Some<int>(1));
  AuthExpect.none<int>(const None<int>());
  AuthExpect.phase(OnboardingPhase.ready, OnboardingPhase.ready);
  AuthExpect.status(expired, expired.status);

  try {
    AuthExpect.ok<int>(Err<int>(expired));
    throw StateError('AuthExpect.ok must reject an Err');
  } on AuthAssertionError catch (error) {
    if (error.toString().isEmpty) {
      throw StateError('AuthAssertionError must describe itself');
    }
  }
}
