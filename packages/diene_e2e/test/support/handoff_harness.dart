import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';

const String expiredTypeUri = 'https://api.example.com/AppHandoffExpired';
const AppHandoffUser alice = AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');

typedef HttpReply = ({int status, Map<String, String> headers, String body});

/// A stub server with the app-handoff fixture mounted and a raw HTTP client.
class HandoffHarness {
  HandoffHarness._(this.server, this.stub, this._client);

  final StubServer server;
  final AppHandoffStub stub;
  final HttpClient _client;
  DateTime now = DateTime.utc(2026, 7, 21, 12);

  static Future<HandoffHarness> start({
    String mountPath = appHandoffDefaultMount,
  }) async {
    final StubServer server = await StubServer.start();
    final AppHandoffStub stub =
        AppHandoffStub(problemTypeUri: expiredTypeUri, mountPath: mountPath)
          ..addUser(alice)
          ..mintingUser = alice;
    final HandoffHarness harness = HandoffHarness._(server, stub, HttpClient());
    stub.mount(server, now: () => harness.now);
    return harness;
  }

  Future<HttpReply> post(String path, String body) async {
    final HttpClientRequest request = await _client.postUrl(
      Uri.parse('${server.baseUrl}$path'),
    );
    request.write(body);
    final HttpClientResponse response = await request.close();
    final Map<String, String> headers = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      headers[name] = values.join(',');
    });
    return (
      status: response.statusCode,
      headers: headers,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  Future<HttpReply> mintReply() => post(stub.mountPath, '{}');

  Future<String> mint() async =>
      AppHandoffMint.fromJson(decodeObject((await mintReply()).body)).nonce;

  Future<HttpReply> redeem(String body) =>
      post('${stub.mountPath}/$appHandoffRedeemPath', body);

  Future<HttpReply> redeemNonce(String nonce, {String platform = 'android'}) =>
      redeem(
        jsonEncode(
          AppHandoffRedeemRequest(
            nonce: nonce,
            device: AppHandoffDevice(platform: platform),
          ).toJson(),
        ),
      );

  Future<void> close() async {
    _client.close(force: true);
    await server.close();
  }
}

Map<String, Object?> decodeObject(String body) =>
    (jsonDecode(body)! as Map<Object?, Object?>).cast<String, Object?>();
