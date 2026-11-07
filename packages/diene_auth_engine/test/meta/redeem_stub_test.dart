import 'dart:async';
import 'dart:convert';

import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const String _nonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Map<String, Object?> _body({Map<String, Object?>? device, Object? nonce}) =>
    <String, Object?>{
      'nonce': nonce ?? _nonce,
      'device': device ?? <String, Object?>{'platform': 'ios'},
    };

Future<http.Response> _post(
  FakeRedeemHttpClient server,
  String path,
  Object? body,
) => server.post(
  Uri.parse('https://api.example.test$path'),
  body: body is String ? body : jsonEncode(body),
);

void main() {
  group('FakeRedeemHttpClient', () {
    test('answers a valid redeem at the default mount', () async {
      // Arrange
      final FakeRedeemHttpClient server = FakeRedeemHttpClient();

      // Act
      final http.Response response = await _post(
        server,
        '/app-handoff/redeem',
        _body(),
      );

      // Assert
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), <String, Object?>{
        'token': 'one-time-token',
        'email': 'user@example.com',
        'expiresIn': 120,
      });
      expect(server.bodies.single, _body());
    });

    test('matches the real HTTP client at a custom mount', () async {
      // Arrange
      final FakeRedeemHttpClient server = FakeRedeemHttpClient(
        mount: '/auth/handoff',
        token: 'tok',
        email: 'a@b.test',
      );
      final HttpAppHandoffApi api = HttpAppHandoffApi(
        base: Uri.parse('https://api.example.test'),
        redeemPath: '/auth/handoff/redeem',
        client: server,
      );

      // Act
      final Result<RedeemResult> result = await api.redeem(
        nonce: _nonce,
        device: const DeviceInfo(platform: 'android', model: 'Pixel 9'),
      );

      // Assert
      final RedeemResult redeemed = AuthExpect.ok(result);
      expect(redeemed.token, 'tok');
      expect(redeemed.email, 'a@b.test');
      expect(server.requests.single.path, '/auth/handoff/redeem');
    });

    test('refuses a doubled segment, a wrong mount and a GET', () async {
      // Arrange
      final FakeRedeemHttpClient server = FakeRedeemHttpClient();

      // Act
      final List<int> codes = <int>[
        (await _post(
          server,
          '/app-handoff/app-handoff/redeem',
          _body(),
        )).statusCode,
        (await _post(server, '/redeem', _body())).statusCode,
        (await server.get(
          Uri.parse('https://api.example.test/app-handoff/redeem'),
        )).statusCode,
      ];

      // Assert
      expect(codes, <int>[404, 404, 404]);
      expect(server.bodies.last, isEmpty);
    });

    test('refuses malformed bodies', () async {
      // Arrange
      final FakeRedeemHttpClient server = FakeRedeemHttpClient();
      final List<Object?> bodies = <Object?>[
        <String, Object?>{..._body(), 'extra': 1},
        _body(device: <String, Object?>{'platform': 'android', 'serial': 'x'}),
        _body(device: <String, Object?>{}),
        _body(nonce: 'short'),
        <String, Object?>{'nonce': _nonce},
        '[]',
      ];

      // Act
      final List<int> codes = <int>[
        for (final Object? body in bodies)
          (await _post(server, '/app-handoff/redeem', body)).statusCode,
      ];

      // Assert
      expect(codes, everyElement(400));
    });

    test('replies with a scripted failure status', () async {
      // Arrange
      final FakeRedeemHttpClient server = FakeRedeemHttpClient(status: 410);

      // Act
      final http.Response response = await _post(
        server,
        '/app-handoff/redeem',
        _body(),
      );

      // Assert
      expect(response.statusCode, 410);
    });

    test('reads a streamed request as an empty body', () async {
      // Arrange
      final FakeRedeemHttpClient server = FakeRedeemHttpClient();
      final http.StreamedRequest request = http.StreamedRequest(
        'POST',
        Uri.parse('https://api.example.test/app-handoff/redeem'),
      );
      unawaited(request.sink.close());

      // Act
      final http.StreamedResponse response = await server.send(request);

      // Assert
      expect(response.statusCode, 400);
      expect(server.bodies.single, isEmpty);
    });
  });
}
