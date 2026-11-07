import 'dart:convert';
import 'dart:io' as io;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late io.HttpServer server;
  late Uri base;
  late int deadPort;

  setUpAll(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((io.HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = 200
        ..headers.contentType = io.ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'method': request.method,
            'echo': body,
            'auth': request.headers.value('authorization'),
          }),
        );
      await request.response.close();
    });
    final io.ServerSocket probe = await io.ServerSocket.bind(
      io.InternetAddress.loopbackIPv4,
      0,
    );
    deadPort = probe.port;
    await probe.close();
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('sends every verb, writes the body, and passes headers', () async {
    // Arrange
    final IoHttpTransport transport = IoHttpTransport();
    addTearDown(transport.close);

    // Act
    for (final HttpMethod method in HttpMethod.values) {
      final TransportOutcome outcome = await transport.send(
        HttpRequest(
          method: method,
          url: base.replace(path: '/echo'),
          headers: const <String, String>{'Authorization': 'Bearer t'},
          body: method == HttpMethod.get || method == HttpMethod.head
              ? null
              : 'payload-${method.name}',
        ),
      );

      // Assert
      expect(outcome, isA<Received>());
      final Received received = outcome as Received;
      expect(received.response.status, 200);
      if (method != HttpMethod.head) {
        final Map<String, Object?> decoded =
            jsonDecode(received.response.body) as Map<String, Object?>;
        expect(decoded['method'], method.name.toUpperCase());
        expect(decoded['auth'], 'Bearer t');
        if (method != HttpMethod.get) {
          expect(decoded['echo'], 'payload-${method.name}');
        }
      }
    }
  });

  test('a refused connection is a NetworkFailure', () async {
    // Arrange
    final IoHttpTransport transport = IoHttpTransport(
      timeout: const Duration(seconds: 2),
    );
    addTearDown(transport.close);

    // Act
    final TransportOutcome outcome = await transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: Uri.parse('http://127.0.0.1:$deadPort/x'),
      ),
    );

    // Assert
    expect(outcome, isA<NetworkFailure>());
  });
}
