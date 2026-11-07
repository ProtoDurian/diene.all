import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/handoff_harness.dart';

const String _upstreamPath = 'test/fixtures/c0/upstream';

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

String? _ownerNonce(Map<String, Object?> carrier) {
  if (carrier.containsKey('text')) {
    return AppHandoffCarrier.parseCanonical(carrier['text']! as String)?.nonce;
  }
  if (carrier.containsKey('androidReferrer')) {
    return AppHandoffCarrier.parseAndroidReferrer(
      carrier['androidReferrer']! as String,
    )?.nonce;
  }
  return AppHandoffCarrier.parseClipboard(
    carrier['clipboard']! as String,
  )?.nonce;
}

String? _e2eNonce(Map<String, Object?> carrier) {
  if (carrier.containsKey('text')) {
    return parseAppHandoffCarrier(carrier['text'] as String?);
  }
  if (carrier.containsKey('androidReferrer')) {
    return parseAppHandoffInstallReferrer(
      carrier['androidReferrer'] as String?,
    );
  }
  return parseAppHandoffClipboard(carrier['clipboard'] as String?);
}

(String platform, String raw) _driverInput(Map<String, Object?> carrier) =>
    carrier.containsKey('androidReferrer')
    ? ('android', carrier['androidReferrer']! as String)
    : ('ios', (carrier['text'] ?? carrier['clipboard'])! as String);

Map<String, Object?> _withNonce(Map<String, Object?> body, String nonce) =>
    <String, Object?>{...body, 'nonce': nonce};

void main() {
  final Map<String, Object?> manifest = _object(_readJson('manifest.json'));
  final Map<String, Object?> vectors = _object(manifest['vectors']);
  final Map<String, Object?> handoff = _object(_readJson('app_handoff.json'));
  final Map<String, Object?> carriers = _object(handoff['carriers']);
  final Map<String, Object?> requests = _object(handoff['redeemRequests']);

  test('the manifest pins the upstream cases this package uses', () {
    // Arrange
    final Map<String, Object?> sources = _object(manifest['sources']);

    // Act
    final Set<String> vendored = Directory(_upstreamPath)
        .listSync()
        .map((FileSystemEntity f) => f.uri.pathSegments.last)
        .where((String f) => f != 'manifest.json')
        .toSet();
    final Set<String> skipped = _objects(
      manifest['skipped'],
    ).map((Map<String, Object?> s) => '${s['path']}#${s['pointer']}').toSet();

    // Assert
    expect(vendored, vectors.keys.toSet());
    expect(manifest['authority'], 'c0-fixtures-r2');
    expect(manifest['commit'], 'fe77520d591f81a9762c40ebf68dc9c0106502d3');
    expect(sources.keys.toSet(), <String>{
      'contracts/c0/cases/identity.json',
      'contracts/c0/cases/problem.json',
    });
    for (final Object? raw in vectors.values) {
      final Map<String, Object?> entry = _object(raw);
      expect(sources.keys, contains(entry['path']));
      expect(skipped, isNot(contains('${entry['path']}#${entry['pointer']}')));
      expect(entry['reproduce'], contains('${manifest['commit']}'));
    }
    expect(vectors.keys.toSet(), <String>{
      'app_handoff.json',
      'problem_extensions.json',
      'problem_members.json',
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

      test('$name file bytes', () {
        // Arrange
        final Map<String, Object?> entry = _object(raw);

        // Act
        final String digest = sha256
            .convert(File('$_upstreamPath/$name').readAsBytesSync())
            .toString();

        // Assert
        expect(
          digest,
          entry['fileSha256'],
          reason: 'upstream vector "$name" bytes drifted from the manifest',
        );
      });
    });
  });

  group('carriers', () {
    test('the carrier prefix and nonce rules match', () {
      // Arrange
      final RegExp pattern = RegExp(handoff['noncePattern']! as String);
      final Random random = Random(7);
      final List<String> nonces = <String>[
        for (int i = 0; i < 32; i++)
          base64Url
              .encode(List<int>.generate(32, (_) => random.nextInt(256)))
              .replaceAll('=', ''),
      ];

      // Act
      final List<bool> valid = nonces.map(isValidAppHandoffNonce).toList();

      // Assert
      expect(
        '$appHandoffCarrierScheme:$appHandoffCarrierVersion:',
        handoff['carrierPrefix'],
      );
      expect(appHandoffNonceLength, handoff['nonceLength']);
      expect(handoff['nonceEncoding'], 'rfc4648-base64url-no-padding');
      expect(valid, everyElement(isTrue));
      for (final String nonce in nonces) {
        expect(pattern.hasMatch(nonce), isTrue, reason: nonce);
      }
    });

    for (final Map<String, Object?> carrier in _objects(carriers['valid'])) {
      test('valid ${carrier['name']}: both codecs give the nonce', () {
        // Arrange
        final String nonce = carrier['nonce']! as String;

        // Act
        final String? ours = _e2eNonce(carrier);
        final String? owner = _ownerNonce(carrier);

        // Assert
        expect(ours, nonce);
        expect(owner, nonce);
        expect(isValidAppHandoffNonce(nonce), isTrue);
        if (carrier.containsKey('text')) {
          expect(buildAppHandoffCarrier(nonce), carrier['text']);
        }
        if (carrier.containsKey('androidReferrer')) {
          expect(
            parseAppHandoffInstallReferrer(
              buildAppHandoffInstallReferrer(
                nonce,
                extraFields: <String, String>{'utm_source': 'play'},
              ),
            ),
            nonce,
          );
        }
      });
    }

    for (final Map<String, Object?> carrier in _objects(carriers['invalid'])) {
      test('invalid ${carrier['name']}: both codecs refuse it', () {
        // Arrange
        final Map<String, Object?> input = carrier;

        // Act
        final String? ours = _e2eNonce(input);
        final String? owner = _ownerNonce(input);

        // Assert
        expect(ours, isNull);
        expect(owner, isNull);
      });
    }
  });

  group('deferred-login driver', () {
    late HandoffHarness h;

    setUp(() async => h = await HandoffHarness.start());
    tearDown(() => h.close());

    for (final Map<String, Object?> carrier in _objects(carriers['valid'])) {
      test(
        'valid ${carrier['name']}: the driver sends the vector nonce',
        () async {
          // Arrange
          final (String platform, String raw) = _driverInput(carrier);
          final DeferredLoginJourney driver = DeferredLoginJourney(
            baseUrl: h.server.baseUrl,
            platform: platform,
          );

          // Act
          final DeferredLoginResult result = await driver.redeemCarrier(raw);
          driver.close();

          // Assert
          expect(
            result.outcome,
            DeferredLoginJourneyOutcome.interactiveFallback,
          );
          final StubRequest sent = h.server.requests.single;
          expect(sent.path, '${handoff['defaultMount']}/redeem');
          expect(sent.jsonBody(), <String, Object?>{
            'nonce': carrier['nonce'],
            'device': <String, Object?>{'platform': platform},
          });
        },
      );
    }

    for (final Map<String, Object?> carrier in _objects(carriers['invalid'])) {
      test(
        'invalid ${carrier['name']}: no request, interactive login',
        () async {
          // Arrange
          final (String platform, String raw) = _driverInput(carrier);
          final DeferredLoginJourney driver = DeferredLoginJourney(
            baseUrl: h.server.baseUrl,
            platform: platform,
          );

          // Act
          final DeferredLoginResult result = await driver.redeemCarrier(raw);
          driver.close();

          // Assert
          expect(
            result.outcome,
            DeferredLoginJourneyOutcome.interactiveFallback,
          );
          expect(result.redeem, isNull);
          expect(h.server.requests, isEmpty);
        },
      );
    }
  });

  group('routes', () {
    for (final String mount in <String>[
      handoff['defaultMount']! as String,
      '/auth/handoff',
    ]) {
      test('mint and redeem are served at $mount', () async {
        // Arrange
        final HandoffHarness h = await HandoffHarness.start(mountPath: mount);
        addTearDown(h.close);
        final Map<String, Object?> mintRoute = _object(handoff['mintRoute']);
        final Map<String, Object?> redeemRoute = _object(
          handoff['redeemRoute'],
        );
        String path(Map<String, Object?> route) =>
            (route['path']! as String).replaceAll('{mount}', mount);

        // Act
        final HttpReply mint = await h.post(path(mintRoute), '{}');
        final String nonce = AppHandoffMint.fromJson(
          decodeObject(mint.body),
        ).nonce;
        final DeferredLoginJourney driver = DeferredLoginJourney(
          baseUrl: h.server.baseUrl,
          mountPath: mount,
          platform: 'ios',
        );
        final DeferredLoginResult result = await driver.redeemCarrier(
          buildAppHandoffCarrier(nonce),
        );
        driver.close();

        // Assert
        expect(mintRoute['method'], 'POST');
        expect(redeemRoute['method'], 'POST');
        expect(mint.status, 200);
        expect(decodeObject(mint.body).keys.toSet(), <String>{
          'nonce',
          'expiresAt',
        });
        expect(h.stub.mountPath, mount);
        expect(h.server.handlerFor('POST', path(mintRoute)), isNotNull);
        expect(h.server.handlerFor('POST', path(redeemRoute)), isNotNull);
        expect(result.outcome, DeferredLoginJourneyOutcome.redeemed);
        expect(h.server.requests.last.path, path(redeemRoute));
        expect(
          h.server.requests.map((StubRequest r) => r.path),
          isNot(contains('$mount/app-handoff/redeem')),
        );
      });
    }

    test('the default mount matches', () {
      // Arrange
      final AppHandoffStub stub = AppHandoffStub(
        problemTypeUri: expiredTypeUri,
      );

      // Act
      final String mount = stub.mountPath;

      // Assert
      expect(mount, handoff['defaultMount']);
      expect(appHandoffDefaultMount, handoff['defaultMount']);
    });
  });

  group('nonce lifecycle', () {
    late HandoffHarness h;

    setUp(() async => h = await HandoffHarness.start());
    tearDown(() => h.close());

    test('a minted nonce follows the nonce pattern', () async {
      // Arrange
      final RegExp pattern = RegExp(handoff['noncePattern']! as String);

      // Act
      final List<String> nonces = <String>[
        for (int i = 0; i < 8; i++) await h.mint(),
      ];

      // Assert
      for (final String nonce in nonces) {
        expect(pattern.hasMatch(nonce), isTrue, reason: nonce);
        expect(base64Url.decode('$nonce='), hasLength(32));
      }
      expect(nonces.toSet(), hasLength(8));
    });

    test('the nonce lives exactly the vector lifetime', () async {
      // Arrange
      final Duration ttl = Duration(
        minutes: handoff['nonceTtlMinutes']! as int,
      );
      final DateTime minted = h.now;
      final HttpReply first = await h.mintReply();
      final String late = await h.mint();

      // Act
      h.now = minted.add(ttl).subtract(const Duration(microseconds: 1));
      final HttpReply inside = await h.redeemNonce(
        AppHandoffMint.fromJson(decodeObject(first.body)).nonce,
      );
      h.now = minted.add(ttl);
      final HttpReply after = await h.redeemNonce(late);

      // Assert
      expect(AppHandoffStub.nonceTtl, ttl);
      expect(
        DateTime.parse(
          AppHandoffMint.fromJson(decodeObject(first.body)).expiresAt,
        ),
        minted.add(ttl),
      );
      expect(inside.status, 200);
      expect(after.status, 410);
    });

    test('the expiry body is the generic problem with no instance', () async {
      // Arrange
      final Map<String, Object?> problem = _object(
        handoff['genericExpiryProblem'],
      );
      final Set<String> allowed = <String>{
        ...(_readJson('problem_members.json')! as List<Object?>).cast<String>(),
        ...(_readJson('problem_extensions.json')! as List<Object?>)
            .cast<String>(),
      };

      // Act
      final HttpReply reply = await h.redeemNonce('A' * 43);
      final Map<String, Object?> body = decodeObject(reply.body);

      // Assert
      expect(reply.status, problem['status']);
      expect(AppHandoffExpired.problemId, problem['id']);
      expect(body, <String, Object?>{
        'type': expiredTypeUri,
        'title': problem['title'],
        'status': problem['status'],
        'detail': problem['detail'],
        'data': problem['data'],
      });
      expect(allowed.containsAll(body.keys), isTrue);
      expect(body.containsKey('instance'), isFalse);
      expect(reply.headers['cache-control'], 'no-store');
    });
  });

  group('redeem requests', () {
    late HandoffHarness h;

    setUp(() async => h = await HandoffHarness.start());
    tearDown(() => h.close());

    for (final Map<String, Object?> vector in _objects(requests['valid'])) {
      test('valid ${vector['name']} gives a one-time token', () async {
        // Arrange
        final Map<String, Object?> body = _object(vector['body']);
        final String nonce = await h.mint();

        // Act
        final HttpReply reply = await h.redeem(
          jsonEncode(_withNonce(body, nonce)),
        );
        final Map<String, Object?> response = decodeObject(reply.body);

        // Assert
        expect(reply.status, 200);
        expect(response.keys.toList(), handoff['redeemSuccessKeys']);
        expect(response['email'], alice.primaryEmail);
        expect(response['expiresIn'], handoff['oneTimeTokenExpiresInSeconds']);
        expect(appHandoffTokenExpiresInSeconds, response['expiresIn']);
        expect(AppHandoffRedeemRequest.fromJson(body).toJson(), body);
      });
    }

    for (final Map<String, Object?> vector in _objects(requests['invalid'])) {
      test(
        'invalid ${vector['name']} is refused and keeps the nonce',
        () async {
          // Arrange
          final Map<String, Object?> body = _object(vector['body']);
          final String nonce = await h.mint();

          // Act
          final HttpReply reply = await h.redeem(
            jsonEncode(_withNonce(body, nonce)),
          );
          final HttpReply retry = await h.redeemNonce(nonce);

          // Assert
          expect(reply.status, 410);
          expect(decodeObject(reply.body), h.stub.expiredBody);
          expect(retry.status, 200);
        },
      );
    }

    test('the auth engine client redeems against the stub', () async {
      // Arrange
      final String nonce = await h.mint();
      final FakeInstallReferrerSource referrer = FakeInstallReferrerSource(
        buildAppHandoffInstallReferrer(nonce),
      );
      final DeferredLoginClient client = DeferredLoginClient(
        api: HttpAppHandoffApi(
          base: Uri.parse(h.server.baseUrl),
          redeemPath: '${handoff['defaultMount']}/redeem',
        ),
        device: const DeviceInfo(platform: 'android'),
        referrer: referrer,
      );

      // Act
      final DeferredLoginOutcome outcome = await client.prepare();
      final DeferredLoginOutcome replay = await client.prepare();

      // Assert
      expect(referrer.processed, isTrue);
      final DeferredLoginReady ready = outcome as DeferredLoginReady;
      expect(ready.extraParams.keys.toSet(), <String>{
        'one_time_token',
        'login_hint',
      });
      expect(ready.extraParams['login_hint'], alice.primaryEmail);
      expect(replay, isA<DeferredLoginFallback>());
      expect(h.server.requests.last.jsonBody()['nonce'], nonce);
    });
  });
}
