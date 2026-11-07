// Mint a carrier on the stub, drive the deferred-login journey, then assert.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';

Future<void> main() async {
  final StubServer server = await StubServer.start();
  final AppHandoffStub handoff = AppHandoffStub(
    problemTypeUri: 'https://api.example.com/AppHandoffExpired',
  )..addUser(const AppHandoffUser(sub: 'user-1', primaryEmail: 'a@b.com'));
  handoff.mount(server);

  handoff.mintingUser = const AppHandoffUser(
    sub: 'user-1',
    primaryEmail: 'a@b.com',
  );

  final DeferredLoginJourney journey = DeferredLoginJourney(
    baseUrl: server.baseUrl,
    platform: 'android',
  );

  final HttpClient client = HttpClient();
  final HttpClientRequest mintRequest = await client.postUrl(
    Uri.parse('${server.baseUrl}${handoff.mountPath}'),
  );
  mintRequest.write('{}');
  final HttpClientResponse mintResponse = await mintRequest.close();
  final String mintBody = await utf8.decoder.bind(mintResponse).join();
  final String nonce = AppHandoffMint.fromJson(
    (jsonDecode(mintBody) as Map<Object?, Object?>).map(
      (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v),
    ),
  ).nonce;

  final String referrer = buildAppHandoffInstallReferrer(
    nonce,
    extraFields: <String, String>{
      'utm_source': 'play',
      'utm_campaign': 'launch',
    },
  );

  final Journey flow = Journey('deferred login', <JourneyStep>[
    JourneyStep('carrier redeems into a one-time token', () async {
      final DeferredLoginResult result = await journey.redeemCarrier(referrer);
      return result.outcome == DeferredLoginJourneyOutcome.redeemed &&
          result.redeem != null;
    }),
    JourneyStep('a replayed nonce is refused', () async {
      final DeferredLoginResult replay = await journey.redeemNonce(nonce);
      return replay.outcome == DeferredLoginJourneyOutcome.interactiveFallback;
    }),
  ]);

  final JourneyResult outcome = await flow.run();

  expectJourneyOk(outcome);
  expectTrue(server.requests.isNotEmpty, 'the journey must reach the server');
  print(
    'journey ${flow.name}: ${outcome.steps.length} steps, ok=${outcome.ok}',
  );

  const Result<int> resolved = Ok<int>(1);
  print('bundled Result resolves to ${expectOk(resolved)}');

  client.close(force: true);
  await server.close();
  journey.close();
}
