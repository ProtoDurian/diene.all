library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/src/generated/export.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: module,
);

RescueConfig _disabledRescue() => RescueConfig(
  enabled: false,
  issuer: Uri.parse('https://unused.example'),
  catalogHosts: const <String>[],
  endpointSuffixAllowlist: const <String>[],
);

({Dio dio, FakeHttpTransport transport}) _wired() {
  final FakeHttpTransport transport = FakeHttpTransport(
    (HttpRequest _) => Received(
      HttpResponse(
        status: 200,
        headers: const <String, String>{'content-type': 'application/json'},
        body: '{"id":"usr_1","email":"a@example.test"}',
      ),
    ),
  );
  final ApiEngine engine = ApiEngine.fromConfig(
    ApiEngineConfig(
      backends: <BackendConfig>[
        BackendConfig(
          coordinate: _coord('a'),
          baseUrl: Uri.parse('https://primary.example.com/api'),
        ),
      ],
      rescue: _disabledRescue(),
    ),
    transport: transport,
  );
  final Backend backend = engine.backend(_coord('a'))!;
  final Dio dio = Dio(BaseOptions(baseUrl: backend.config.baseUrl.toString()))
    ..httpClientAdapter = BackendClientAdapter(backend);
  return (dio: dio, transport: transport);
}

void main() {
  group('UsersClient resolves its base URL three ways', () {
    test('with NO baseUrl it uses dio\'s own', () async {
      // Arrange
      final ({Dio dio, FakeHttpTransport transport}) w = _wired();

      // Act
      final UserProfile profile = await UsersClient(w.dio).getUser(id: 'usr_1');

      // Assert
      expect(profile.id, 'usr_1');
      expect(w.transport.sent.single.url.host, 'primary.example.com');
    });

    test('an EMPTY baseUrl also falls back to dio\'s own', () async {
      // Arrange
      final ({Dio dio, FakeHttpTransport transport}) w = _wired();

      // Act
      await UsersClient(w.dio, baseUrl: '   ').getUser(id: 'usr_1');

      // Assert
      expect(w.transport.sent.single.url.host, 'primary.example.com');
    });

    test(
      'an ABSOLUTE baseUrl is resolved but the BACKEND host still wins',
      () async {
        // Arrange
        final ({Dio dio, FakeHttpTransport transport}) w = _wired();

        // Act
        await UsersClient(
          w.dio,
          baseUrl: 'https://override.example.com/v2',
        ).getUser(id: 'usr_1');

        // Assert
        expect(w.transport.sent.single.url.host, 'primary.example.com');
      },
    );

    test('a RELATIVE baseUrl resolves against dio\'s', () async {
      // Arrange
      final ({Dio dio, FakeHttpTransport transport}) w = _wired();

      // Act
      await UsersClient(w.dio, baseUrl: 'v3/').getUser(id: 'usr_1');

      // Assert
      final Uri sent = w.transport.sent.single.url;
      expect(sent.host, 'primary.example.com');
      expect(sent.path, contains('v3'));
    });
  });
}
