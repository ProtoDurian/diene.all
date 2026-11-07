import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _upstreamPath = 'test/fixtures/c0/upstream';
const String _nonDefaultMount = '/auth/handoff';

Map<String, Object?> _object(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List<Object?>).map(_object).toList();

Object? _sortKeys(Object? value) {
  if (value is Map<Object?, Object?>) {
    final List<String> keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sortKeys(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_sortKeys).toList();
  }
  return value;
}

String _canonical(Object? value) => '${jsonEncode(_sortKeys(value))}\n';

Object? _readJson(String name) =>
    jsonDecode(File('$_upstreamPath/$name').readAsStringSync());

Map<String, Object?> _vector(String name) => _object(_readJson(name));

AuthEngineConfig _config({String? mount}) =>
    AuthEngineConfig.fromBlock(<String, Object?>{
      'issuer': 'https://api.lithium.aldehyde.lapras.cluster.atomi.cloud/oidc',
      'endpoint': 'https://api.lithium.aldehyde.lapras.cluster.atomi.cloud',
      'appId': 'app',
      'redirectUri': 'io.atomi.app://callback',
      'appHandoffMount': ?mount,
    });

LandscapeSelectorDoc _doc(Object? json) =>
    LandscapeSelectorDoc.fromJson(_object(json));

void main() {
  final Map<String, Object?> manifest = _vector('manifest.json');
  final Map<String, Object?> vectors = _object(manifest['vectors']);
  final DateTime now = DateTime.utc(2026, 11, 7);

  test('the manifest pins the upstream identity cases', () {
    // Arrange
    final Map<String, Object?> source = _object(manifest['source']);

    // Act
    final Set<String> names = vectors.keys.toSet();

    // Assert
    expect(manifest['authority'], 'c0-fixtures-r2');
    expect(source['commit'], 'fe77520d591f81a9762c40ebf68dc9c0106502d3');
    expect(source['path'], 'contracts/c0/cases/identity.json');
    expect(names, <String>{
      'app_handoff.json',
      'doc_b.json',
      'home_claim.json',
      'onboarding_claim.json',
      'resource_audience.json',
      'token_lifetimes.json',
    });
  });

  group('upstream vector digests', () {
    vectors.forEach((String name, Object? raw) {
      test(name, () {
        // Arrange
        final Map<String, Object?> entry = _object(raw);

        // Act
        final String digest = sha256
            .convert(utf8.encode(_canonical(_readJson(name))))
            .toString();

        // Assert
        expect(
          digest,
          entry['sha256'],
          reason: 'upstream vector "$name" digest drifted from the manifest',
        );
      });
    });
  });

  group('app handoff', () {
    final Map<String, Object?> handoff = _vector('app_handoff.json');
    final Map<String, Object?> carriers = _object(handoff['carriers']);

    test('fixed constants and routes match', () {
      // Arrange
      final String nonce = base64Url
          .encode(List<int>.filled(32, 7))
          .replaceAll('=', '');
      final String route = _object(handoff['redeemRoute'])['path']! as String;

      // Act
      final AppHandoffCarrier? carrier = AppHandoffCarrier.parseCanonical(
        '${handoff['carrierPrefix']}$nonce',
      );

      // Assert
      expect(handoff['nonceEncoding'], 'rfc4648-base64url-no-padding');
      expect(nonce.length, handoff['nonceLength']);
      expect(RegExp(handoff['noncePattern']! as String).hasMatch(nonce), true);
      expect(carrier!.canonicalText, '${handoff['carrierPrefix']}$nonce');
      expect(handoff['defaultMount'], AppHandoffConstants.defaultMount);
      expect(
        AppHandoffConstants.nonceTtl,
        Duration(minutes: handoff['nonceTtlMinutes']! as int),
      );
      expect(
        AppHandoffConstants.oneTimeTokenExpiresInSeconds,
        handoff['oneTimeTokenExpiresInSeconds'],
      );
      expect(_object(handoff['redeemRoute'])['method'], 'POST');
      expect(
        _config().redeemPath,
        route.replaceAll('{mount}', AppHandoffConstants.defaultMount),
      );
      expect(
        _config(mount: _nonDefaultMount).redeemPath,
        route.replaceAll('{mount}', _nonDefaultMount),
      );
    });

    for (final Map<String, Object?> sample in _objects(carriers['valid'])) {
      test('valid carrier ${sample['name']}', () {
        // Arrange
        final Object? text = sample['text'];
        final Object? referrer = sample['androidReferrer'];
        final Object? clipboard = sample['clipboard'];

        // Act
        final AppHandoffCarrier? carrier = text is String
            ? AppHandoffCarrier.parseCanonical(text)
            : referrer is String
            ? AppHandoffCarrier.parseAndroidReferrer(referrer)
            : AppHandoffCarrier.parseClipboard(clipboard! as String);

        // Assert
        expect(carrier?.nonce, sample['nonce']);
      });
    }

    for (final Map<String, Object?> sample in _objects(carriers['invalid'])) {
      test('invalid carrier ${sample['name']}', () {
        // Arrange
        final Object? text = sample['text'];

        // Act
        final List<AppHandoffCarrier?> parsed = text is String
            ? <AppHandoffCarrier?>[
                AppHandoffCarrier.parseCanonical(text),
                AppHandoffCarrier.parseClipboard(text),
              ]
            : <AppHandoffCarrier?>[
                AppHandoffCarrier.parseAndroidReferrer(
                  sample['androidReferrer']! as String,
                ),
              ];

        // Assert
        expect(parsed, everyElement(isNull));
      });
    }

    for (final String mount in <String>[
      AppHandoffConstants.defaultMount,
      _nonDefaultMount,
    ]) {
      test('clipboard carrier -> POST $mount/redeem -> signIn', () async {
        // Arrange
        final AuthEngineConfig config = _config(mount: mount);
        final FakeRedeemHttpClient server = FakeRedeemHttpClient(mount: mount);
        final Map<String, Object?> sample = _objects(
          carriers['valid'],
        ).firstWhere((Map<String, Object?> s) => s.containsKey('clipboard'));
        final FakeClipboardCarrierSource clipboard = FakeClipboardCarrierSource(
          sample['clipboard']! as String,
        );
        final DeferredLoginClient client = DeferredLoginClient(
          api: HttpAppHandoffApi(
            base: Uri.parse('https://api.example.test'),
            redeemPath: config.redeemPath,
            client: server,
          ),
          device: const DeviceInfo(platform: 'ios'),
          clipboard: clipboard,
        );
        final FakeAuthProvider provider = FakeAuthProvider(
          onSignIn: () => AuthFixtures.sessionTokens(now: now),
        );
        final SessionController session = SessionController(
          provider: provider,
          now: () => now,
        );

        // Act
        final DeferredLoginOutcome outcome = await client.prepare();
        final Map<String, String> extraParams =
            (outcome as DeferredLoginReady).extraParams;
        final Result<SessionTokens> signedIn = await session.signIn(
          extraParams: extraParams,
        );

        // Assert
        final String path = server.requests.single.path;
        expect(path, '$mount/redeem');
        expect('app-handoff'.allMatches(path).length, lessThanOrEqualTo(1));
        expect(server.bodies.single['nonce'], sample['nonce']);
        expect(clipboard.cleared, true);
        expect(extraParams, <String, String>{
          'one_time_token': server.token,
          'login_hint': server.email,
        });
        expect(signedIn.isOk, true);
        expect(provider.lastExtraParams, extraParams);
      });
    }

    test('valid redeem bodies equal what the client sends', () async {
      // Arrange
      final List<Map<String, Object?>> samples = _objects(
        _object(handoff['redeemRequests'])['valid'],
      );
      final FakeRedeemHttpClient server = FakeRedeemHttpClient();
      final HttpAppHandoffApi api = HttpAppHandoffApi(
        base: Uri.parse('https://api.example.test'),
        redeemPath: _config().redeemPath,
        client: server,
      );

      // Act
      for (final Map<String, Object?> sample in samples) {
        final Map<String, Object?> body = _object(sample['body']);
        final Map<String, Object?> device = _object(body['device']);
        await api.redeem(
          nonce: body['nonce']! as String,
          device: DeviceInfo(
            platform: device['platform']! as String,
            appVersion: device['appVersion'] as String?,
            osVersion: device['osVersion'] as String?,
            model: device['model'] as String?,
          ),
        );
      }

      // Assert
      expect(
        server.bodies.map(_canonical).toList(),
        samples.map((Map<String, Object?> s) => _canonical(s['body'])).toList(),
      );
      expect(server.bodies.every(FakeRedeemHttpClient.acceptsBody), true);
    });

    test('invalid redeem bodies are refused by the stub', () {
      // Arrange
      final List<Map<String, Object?>> samples = _objects(
        _object(handoff['redeemRequests'])['invalid'],
      );

      // Act
      final List<bool> accepted = samples
          .map((Map<String, Object?> s) => _object(s['body']))
          .map(FakeRedeemHttpClient.acceptsBody)
          .toList();

      // Assert
      expect(accepted, everyElement(false));
    });

    test('a redeem success carries exactly the listed keys', () async {
      // Arrange
      final List<String> keys = (handoff['redeemSuccessKeys']! as List<Object?>)
          .cast<String>();
      final Map<String, Object?> reply = <String, Object?>{
        'token': 'one-time-token',
        'email': 'user@example.com',
        'expiresIn': handoff['oneTimeTokenExpiresInSeconds'],
      };
      final HttpAppHandoffApi api = HttpAppHandoffApi(
        base: Uri.parse('https://api.example.test'),
        redeemPath: _config().redeemPath,
        client: MockClient(
          (http.Request request) async => http.Response(jsonEncode(reply), 200),
        ),
      );

      // Act
      final Result<RedeemResult> result = await api.redeem(
        nonce: 'A' * 43,
        device: const DeviceInfo(platform: 'android'),
      );

      // Assert
      expect(reply.keys.toSet(), keys.toSet());
      final RedeemResult redeemed = AuthExpect.ok(result);
      expect(redeemed.token, reply['token']);
      expect(redeemed.email, reply['email']);
      expect(redeemed.expiresIn, reply['expiresIn']);
    });

    test('the expiry problem matches', () {
      // Arrange
      final Map<String, Object?> expected = _object(
        handoff['genericExpiryProblem'],
      );

      // Act
      final Map<String, Object?> problem = appHandoffExpired().toJson();

      // Assert
      expect(problem['status'], expected['status']);
      expect(problem['title'], expected['title']);
      expect(problem['detail'], expected['detail']);
      expect(problem['data'], expected['data']);
      expect(problem['type'], 'urn:diene:problem:app-handoff-expired');
    });
  });

  group('Doc B', () {
    final Map<String, Object?> docB = _vector('doc_b.json');
    final Map<String, Object?> docVectors = _object(docB['vectors']);
    final Map<String, Object?> validDoc = _object(
      _objects(docVectors['valid']).single['doc'],
    );

    test('required keys match the parser', () {
      // Arrange
      final LandscapeSelectorDoc doc = _doc(validDoc);

      // Act
      final Set<String> keys = validDoc.keys.toSet();
      final Set<String> entryKeys = _objects(validDoc['landscapes'])
          .map((Map<String, Object?> e) => e.keys.toSet())
          .reduce((Set<String> a, Set<String> b) => a.intersection(b));

      // Assert
      expect(keys, (docB['requiredKeys']! as List<Object?>).toSet());
      expect(
        entryKeys,
        containsAll(docB['requiredEntryKeys']! as List<Object?>),
      );
      expect(doc.platform, validDoc['platform']);
      expect(doc.tier, validDoc['tier']);
    });

    for (final Map<String, Object?> sample in _objects(docVectors['valid'])) {
      test('valid doc ${sample['name']}', () {
        // Arrange
        final Object? json = sample['doc'];

        // Act
        final LandscapeSelectorDoc doc = _doc(json);

        // Assert
        expect(
          doc.landscapes.map((LandscapeEntry e) => e.name).toList(),
          _objects(
            _object(json)['landscapes'],
          ).map((Map<String, Object?> e) => e['name']).toList(),
        );
      });
    }

    for (final Map<String, Object?> sample in _objects(docVectors['invalid'])) {
      test('invalid doc ${sample['name']} is untrusted', () {
        // Arrange
        final Object? json = sample['doc'];

        // Act
        LandscapeSelectorDoc parse() => _doc(json);

        // Assert
        expect(parse, throwsFormatException);
      });
    }

    test('one bad entry rejects the whole document', () {
      // Arrange
      final Map<String, Object?> bad = _object(
        _objects(docVectors['invalid']).firstWhere(
          (Map<String, Object?> s) => s['name'] == 'url-value-in-metadata',
        )['doc'],
      );
      final Map<String, Object?> mixed = <String, Object?>{
        ...validDoc,
        'landscapes': <Object?>[
          ..._objects(validDoc['landscapes']),
          ..._objects(bad['landscapes']),
        ],
      };

      // Act
      LandscapeSelectorDoc parse() => _doc(mixed);

      // Assert
      expect(parse, throwsFormatException);
    });

    test('a document host outside the allowlist is refused', () async {
      // Arrange
      int requests = 0;
      final HttpLandscapeSelectorSource source = HttpLandscapeSelectorSource(
        docUrl: Uri.parse('https://edge.example.com/doc-b.json'),
        config: _config(),
        client: MockClient((http.Request request) async {
          requests += 1;
          return http.Response(jsonEncode(validDoc), 200);
        }),
      );

      // Act
      Future<LandscapeSelectorDoc> fetch() => source.fetch();

      // Assert
      await expectLater(fetch, throwsFormatException);
      expect(requests, 0);
    });

    test('ping URLs come from landscape names only', () async {
      // Arrange
      final List<Uri> pinged = <Uri>[];
      final LandscapeSelectorClient selector = LandscapeSelectorClient(
        source: FakeLandscapeSelectorSource(doc: _doc(validDoc)),
        pinger: HttpRegionPinger(
          pingUrlOf: (LandscapeEntry e) =>
              Uri.https('${e.name}.ping.cluster.atomi.cloud', '/'),
          client: MockClient((http.Request request) async {
            pinged.add(request.url);
            return http.Response('', 200);
          }),
        ),
      );

      // Act
      final Result<String> home = await selector.selectHome();

      // Assert
      expect(home.isOk, true);
      expect(
        pinged.map((Uri u) => u.host).toSet(),
        _objects(validDoc['landscapes'])
            .map(
              (Map<String, Object?> e) =>
                  '${e['name']}.ping.cluster.atomi.cloud',
            )
            .toSet(),
      );
      expect(jsonEncode(validDoc).contains('://'), false);
    });
  });

  group('home claim', () {
    final Map<String, Object?> homeClaim = _vector('home_claim.json');
    final Map<String, Object?> homeVectors = _object(homeClaim['vectors']);

    HomeClaimResolver resolver(
      Map<String, Object?> claims,
      FakeLandscapeSelectorSource source,
    ) => HomeClaimResolver(
      claimReader: jwtHomeClaimReader(() async => AuthFixtures.jwt(claims)),
      selector: LandscapeSelectorClient(
        source: source,
        pinger: FakeRegionPinger(<String, Duration?>{
          'raichu': const Duration(milliseconds: 5),
        }),
      ),
    );

    FakeLandscapeSelectorSource docSource() => FakeLandscapeSelectorSource(
      doc: _doc(
        _objects(
          _object(_vector('doc_b.json')['vectors'])['valid'],
        ).single['doc'],
      ),
    );

    test('the claim name matches', () {
      // Arrange
      final Object? name = homeClaim['claimName'];

      // Act
      const String actual = Claims.homeLandscape;

      // Assert
      expect(actual, name);
    });

    for (final Map<String, Object?> sample in _objects(
      homeVectors['present'],
    )) {
      test(
        'present ${sample['name']}: home from the claim, no Doc B',
        () async {
          // Arrange
          final Map<String, Object?> claims = _object(sample['claims']);
          final FakeLandscapeSelectorSource source = docSource();

          // Act
          final HomeResolution home = AuthExpect.ok(
            await resolver(claims, source).resolve(),
          );

          // Assert
          expect(Claims.home(claims), sample['expected']);
          expect(home.landscape, sample['expected']);
          expect(home.kind, HomeResolutionKind.fromClaim);
          expect(source.fetchCount, 0);
        },
      );
    }

    for (final Map<String, Object?> sample in _objects(homeVectors['absent'])) {
      test('absent ${sample['name']}: Doc B on every try', () async {
        // Arrange
        final Map<String, Object?> claims = _object(sample['claims']);
        final FakeLandscapeSelectorSource source = docSource();
        final HomeClaimResolver home = resolver(claims, source);

        // Act
        final HomeResolution first = AuthExpect.ok(await home.resolve());
        final HomeResolution retried = AuthExpect.ok(await home.resolve());

        // Assert
        expect(Claims.home(claims), isNull);
        expect(first.kind, HomeResolutionKind.selected);
        expect(retried.kind, HomeResolutionKind.selected);
        expect(source.fetchCount, 2);
      });
    }
  });

  group('onboarding claim', () {
    final Map<String, Object?> claim = _vector('onboarding_claim.json');
    final Map<String, Object?> claimVectors = _object(claim['vectors']);

    for (final Map<String, Object?> sample in _objects(
      claimVectors['present'],
    )) {
      test('present ${sample['name']}', () {
        // Arrange
        final String platform = sample['platform']! as String;
        final String service = sample['service']! as String;

        // Act
        final String key = Claims.registrationKey(
          platform: platform,
          service: service,
        );

        // Assert
        expect(key, sample['expectedKey']);
        expect(_object(sample['claims'])[key], claim['registeredValue']);
        expect(
          Claims.hasRegistration(
            _object(sample['claims']),
            platform: platform,
            service: service,
          ),
          true,
        );
      });
    }

    for (final Map<String, Object?> sample in _objects(
      claimVectors['absent'],
    )) {
      test('absent ${sample['name']}', () {
        // Arrange
        final Map<String, Object?> claims = _object(sample['claims']);

        // Act
        final bool registered = Claims.hasRegistration(
          claims,
          platform: sample['platform']! as String,
          service: sample['service']! as String,
        );

        // Assert
        expect(registered, false);
      });
    }
  });

  group('resource audience', () {
    final Map<String, Object?> audience = _vector('resource_audience.json');
    final Map<String, Object?> audienceVectors = _object(audience['vectors']);

    ResourceKey key(Map<String, Object?> sample) => ResourceKey(
      platform: sample['platform']! as String,
      landscape: sample['landscape']! as String,
      service: sample['service']! as String,
      resourceName: sample['resourceName']! as String,
    );

    String fill(String template, Map<String, Object?> sample) =>
        <String>['resourceName', 'service', 'platform', 'landscape'].fold(
          template,
          (String t, String k) => t.replaceAll('{$k}', '${sample[k]}'),
        );

    for (final Map<String, Object?> sample in _objects(
      audienceVectors['valid'],
    )) {
      test('valid ${sample['name']}', () {
        // Arrange
        final ResourceKey resource = key(sample);

        // Act
        final String aud = resource.audience.toString();

        // Assert
        expect(aud, sample['expectedAudience']);
        expect(aud, fill(audience['audienceTemplate']! as String, sample));
        expect(resource.mapKey, sample['expectedMapKey']);
        expect(
          resource.mapKey,
          fill(audience['mapKeyTemplate']! as String, sample),
        );
      });
    }

    for (final Map<String, Object?> sample in _objects(
      audienceVectors['invalid'],
    )) {
      test('invalid ${sample['name']}', () {
        // Arrange
        final Map<String, Object?> input = sample;

        // Act
        ResourceKey build() => key(input);

        // Assert
        expect(build, throwsFormatException);
      });
    }
  });

  test('token lifetimes match', () {
    // Arrange
    final Map<String, Object?> lifetimes = _vector('token_lifetimes.json');

    // Act
    final Duration access = Duration(
      minutes: lifetimes['accessMinutes']! as int,
    );
    final Duration refresh = Duration(days: lifetimes['refreshDays']! as int);

    // Assert
    expect(TokenLifetimes.access, access);
    expect(TokenLifetimes.refresh, refresh);
    expect(TokenLifetimes.refreshRotating, lifetimes['refreshRotating']);
    expect(TokenLifetimes.remintOnOpen, lifetimes['remintOnOpen']);
  });
}
