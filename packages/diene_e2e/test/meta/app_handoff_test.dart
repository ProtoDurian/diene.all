import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/handoff_harness.dart';

void main() {
  late HandoffHarness h;

  setUp(() async => h = await HandoffHarness.start());
  tearDown(() => h.close());

  group('AppHandoffStub', () {
    test('a user built at runtime is active and present by default', () {
      // Arrange
      final String sub = <String>['u', '9'].join();

      // Act
      final AppHandoffUser user = AppHandoffUser(sub: sub, primaryEmail: null);

      // Assert
      expect(user.sub, 'u9');
      expect(user.primaryEmail, isNull);
      expect(user.isSuspended, isFalse);
      expect(user.deleted, isFalse);
    });

    test('mint then redeem gives a one-time token for the user', () async {
      // Arrange
      final HttpReply mint = await h.mintReply();
      final AppHandoffMint minted = AppHandoffMint.fromJson(
        decodeObject(mint.body),
      );

      // Act
      final HttpReply reply = await h.redeemNonce(minted.nonce);
      final AppHandoffRedeemResponse redeemed =
          AppHandoffRedeemResponse.fromJson(decodeObject(reply.body));

      // Assert
      expect(mint.status, 200);
      expect(mint.headers['cache-control'], 'no-store');
      expect(isValidAppHandoffNonce(minted.nonce), isTrue);
      expect(minted.expiresAt, '2026-07-21T12:15:00.000Z');
      expect(reply.status, 200);
      expect(redeemed.token, startsWith('ott_'));
      expect(redeemed.token, hasLength(4 + appHandoffNonceLength));
      expect(redeemed.email, 'a@b.com');
      expect(redeemed.expiresIn, 120);
    });

    test('a nonce redeems once; the replay gets the expiry body', () async {
      // Arrange
      final String nonce = await h.mint();
      await h.redeemNonce(nonce);

      // Act
      final HttpReply replay = await h.redeemNonce(nonce);

      // Assert
      expect(replay.status, 410);
      expect(decodeObject(replay.body), h.stub.expiredBody);
      expect(h.stub.expiredBody['type'], expiredTypeUri);
    });

    test('mint refuses until mintingUser is set', () async {
      // Arrange
      final StubServer server = await StubServer.start();
      addTearDown(server.close);
      final AppHandoffStub stub = AppHandoffStub(problemTypeUri: expiredTypeUri)
        ..addUser(alice);
      stub.mount(server);
      final StubHandler mint = server.handlerFor('POST', stub.mountPath)!;
      final StubRequest call = StubRequest(
        method: 'POST',
        path: stub.mountPath,
        headers: const <String, String>{},
        body: '{}',
      );

      // Act
      final Object? error = await Future<Object?>(
        () => mint(call),
      ).then<Object?>((Object? _) => null, onError: (Object e) => e);
      stub.mintingUser = alice;
      final StubResponse minted = await mint(call);

      // Assert
      expect(error, isA<StateError>());
      expect(minted.status, 200);
    });

    test('without a clock it uses the real time', () async {
      // Arrange
      final StubServer server = await StubServer.start();
      addTearDown(server.close);
      final AppHandoffStub stub = AppHandoffStub(problemTypeUri: expiredTypeUri)
        ..addUser(alice)
        ..mintingUser = alice;
      final DateTime before = DateTime.now().toUtc();
      stub.mount(server);

      // Act
      final StubResponse minted = await server.handlerFor(
        'POST',
        stub.mountPath,
      )!(StubRequest(method: 'POST', path: '/', headers: const {}, body: ''));
      final DateTime expiresAt = DateTime.parse(
        AppHandoffMint.fromJson(decodeObject(minted.body)).expiresAt,
      );

      // Assert
      expect(expiresAt.isBefore(before.add(AppHandoffStub.nonceTtl)), isFalse);
      expect(
        expiresAt.isAfter(DateTime.now().toUtc().add(AppHandoffStub.nonceTtl)),
        isFalse,
      );
    });

    test('an injected Random gives repeatable nonces', () async {
      // Arrange
      Future<String> mintWith(int seed) async {
        final StubServer server = await StubServer.start();
        addTearDown(server.close);
        final AppHandoffStub stub = AppHandoffStub(
          problemTypeUri: expiredTypeUri,
          random: Random(seed),
        )..mintingUser = alice;
        stub.mount(server);
        final StubResponse minted = await server.handlerFor(
          'POST',
          stub.mountPath,
        )!(StubRequest(method: 'POST', path: '/', headers: const {}, body: ''));
        return AppHandoffMint.fromJson(decodeObject(minted.body)).nonce;
      }

      // Act
      final List<String> nonces = <String>[
        await mintWith(1),
        await mintWith(1),
        await mintWith(2),
      ];

      // Assert
      expect(nonces[0], nonces[1]);
      expect(nonces[0], isNot(nonces[2]));
      expect(nonces.every(isValidAppHandoffNonce), isTrue);
    });

    test(
      'the email check ignores ASCII case and returns the current email',
      () async {
        // Arrange
        h.stub.addUser(
          const AppHandoffUser(sub: 'u1', primaryEmail: 'A@B.com'),
        );
        final String nonce = await h.mint();

        // Act
        final HttpReply reply = await h.redeemNonce(nonce);

        // Assert
        expect(reply.status, 200);
        expect(decodeObject(reply.body)['email'], 'A@B.com');
      },
    );

    test('a body that is not a JSON object is refused', () async {
      // Arrange
      final String nonce = await h.mint();

      // Act
      final List<HttpReply> replies = <HttpReply>[
        for (final String body in <String>['', '{', '[1]', '"x"'])
          await h.redeem(body),
      ];
      final HttpReply valid = await h.redeemNonce(nonce);

      // Assert
      for (final HttpReply reply in replies) {
        expect(reply.status, 410);
        expect(decodeObject(reply.body), h.stub.expiredBody);
      }
      expect(valid.status, 200);
    });

    test('a user missing from the directory is refused', () async {
      // Arrange
      h.stub.mintingUser = const AppHandoffUser(
        sub: 'ghost',
        primaryEmail: 'g@b.com',
      );
      final String nonce = await h.mint();

      // Act
      final HttpReply reply = await h.redeemNonce(nonce);

      // Assert
      expect(reply.status, 410);
      expect(decodeObject(reply.body), h.stub.expiredBody);
    });

    test('a refused nonce is revoked, not returned to active', () async {
      // Arrange
      h.stub.addUser(
        const AppHandoffUser(
          sub: 'u1',
          primaryEmail: 'a@b.com',
          isSuspended: true,
        ),
      );
      final String nonce = await h.mint();
      final HttpReply refused = await h.redeemNonce(nonce);
      h.stub.addUser(alice);

      // Act
      final HttpReply retry = await h.redeemNonce(nonce);

      // Assert
      expect(refused.status, 410);
      expect(retry.status, 410);
    });

    test('every optional device field may be sent', () async {
      // Arrange
      final String nonce = await h.mint();
      const AppHandoffDevice device = AppHandoffDevice(
        platform: 'ios',
        appVersion: '1.2.3',
        osVersion: '18',
        model: 'iPhone',
      );

      // Act
      final HttpReply reply = await h.redeem(
        jsonEncode(<String, Object?>{
          'nonce': nonce,
          'device': device.toJson(),
        }),
      );

      // Assert
      expect(reply.status, 200);
    });

    test('the nonce lifetime is fixed at 15 minutes', () {
      // Arrange
      final AppHandoffStub stub = AppHandoffStub(
        problemTypeUri: expiredTypeUri,
        mountPath: '/custom',
      );

      // Act
      const Duration ttl = AppHandoffStub.nonceTtl;

      // Assert
      expect(ttl, const Duration(minutes: 15));
      expect(stub.mountPath, '/custom');
      expect(stub.mintingUser, isNull);
      expect(AppHandoffNonceState.values, hasLength(4));
    });
  });

  group('DeferredLoginJourney', () {
    DeferredLoginJourney driver(String platform, {String? mount}) =>
        DeferredLoginJourney(
          baseUrl: h.server.baseUrl,
          platform: platform,
          mountPath: mount ?? appHandoffDefaultMount,
        );

    test('an Android referrer is redeemed into a token', () async {
      // Arrange
      final String nonce = await h.mint();
      final DeferredLoginJourney journey = driver('android');
      addTearDown(journey.close);

      // Act
      final DeferredLoginResult result = await journey.redeemCarrier(
        buildAppHandoffInstallReferrer(
          nonce,
          extraFields: <String, String>{'utm_source': 'play'},
        ),
      );

      // Assert
      expect(result.outcome, DeferredLoginJourneyOutcome.redeemed);
      expect(result.redeem!.email, 'a@b.com');
      final StubRequest sent = h.server.requests.last;
      expect(sent.path, '/app-handoff/redeem');
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(sent.jsonBody(), <String, Object?>{
        'nonce': nonce,
        'device': <String, Object?>{'platform': 'android'},
      });
    });

    test('iOS clipboard text is redeemed into a token', () async {
      // Arrange
      final String nonce = await h.mint();
      final DeferredLoginJourney journey = driver('ios');
      addTearDown(journey.close);

      // Act
      final DeferredLoginResult result = await journey.redeemCarrier(
        '  ${buildAppHandoffCarrier(nonce)}\n',
      );

      // Assert
      expect(result.outcome, DeferredLoginJourneyOutcome.redeemed);
      expect(h.server.requests.last.jsonBody()['device'], <String, Object?>{
        'platform': 'ios',
      });
    });

    test('an absent or invalid carrier falls back with no request', () async {
      // Arrange
      final DeferredLoginJourney android = driver('android');
      final DeferredLoginJourney ios = driver('ios');
      addTearDown(android.close);
      addTearDown(ios.close);

      // Act
      final List<DeferredLoginResult> results = <DeferredLoginResult>[
        await android.redeemCarrier(null),
        await android.redeemCarrier('utm_source=play'),
        await android.redeemCarrier('app_handoff=%zz'),
        await ios.redeemCarrier('atomi-app-handoff:v1:AAAA'),
      ];

      // Assert
      for (final DeferredLoginResult r in results) {
        expect(r.outcome, DeferredLoginJourneyOutcome.interactiveFallback);
        expect(r.redeem, isNull);
      }
      expect(h.server.requests, isEmpty);
    });

    test('an expiry response falls back to interactive login', () async {
      // Arrange
      final String nonce = await h.mint();
      final DeferredLoginJourney journey = driver('android');
      addTearDown(journey.close);
      await journey.redeemNonce(nonce);

      // Act
      final DeferredLoginResult replay = await journey.redeemNonce(nonce);

      // Assert
      expect(replay.outcome, DeferredLoginJourneyOutcome.interactiveFallback);
      expect(replay.redeem, isNull);
    });

    test('it posts to the configured mount', () async {
      // Arrange
      final HandoffHarness custom = await HandoffHarness.start(
        mountPath: '/auth/handoff',
      );
      addTearDown(custom.close);
      final String nonce = await custom.mint();
      final DeferredLoginJourney journey = DeferredLoginJourney(
        baseUrl: custom.server.baseUrl,
        mountPath: '/auth/handoff',
        platform: 'android',
      );
      addTearDown(journey.close);

      // Act
      final DeferredLoginResult result = await journey.redeemNonce(nonce);

      // Assert
      expect(journey.mountPath, '/auth/handoff');
      expect(result.outcome, DeferredLoginJourneyOutcome.redeemed);
      expect(custom.server.requests.last.path, '/auth/handoff/redeem');
    });

    test('it uses the injected client, and close closes it', () async {
      // Arrange
      final HttpClient client = HttpClient();
      final DeferredLoginJourney journey = DeferredLoginJourney(
        baseUrl: h.server.baseUrl,
        platform: 'android',
        httpClient: client,
      );

      // Act
      journey.close();

      // Assert
      expect(journey.baseUrl, h.server.baseUrl);
      expect(journey.platform, 'android');
      expect(
        () => client.postUrl(Uri.parse(h.server.baseUrl)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
