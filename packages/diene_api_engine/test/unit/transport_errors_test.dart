library;

import 'dart:io' as io;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IoHttpTransport maps protocol-level faults to NetworkFailure', () {
    test(
      'a TLS handshake against a plain-HTTP server is a NetworkFailure',
      () async {
        // Arrange
        final io.HttpServer plain = await io.HttpServer.bind(
          io.InternetAddress.loopbackIPv4,
          0,
        );
        plain.listen((io.HttpRequest r) async {
          r.response.statusCode = 200;
          await r.response.close();
        });
        addTearDown(() => plain.close(force: true));

        final IoHttpTransport transport = IoHttpTransport(
          timeout: const Duration(seconds: 3),
        );
        addTearDown(transport.close);

        // Act
        final TransportOutcome outcome = await transport.send(
          HttpRequest(
            method: HttpMethod.get,
            url: Uri.parse('https://127.0.0.1:${plain.port}/x'),
          ),
        );

        // Assert
        expect(outcome, isA<NetworkFailure>());

        expect((outcome as NetworkFailure).reason, startsWith('tls: '));
        expect(outcome.cause, isNotNull);
      },
    );

    test('a non-HTTP response body is a NetworkFailure, not a throw', () async {
      // Arrange
      final io.ServerSocket raw = await io.ServerSocket.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      raw.listen((io.Socket s) {
        s.write('NOT-HTTP\r\n\r\n');
        s.destroy();
      });
      addTearDown(raw.close);

      final IoHttpTransport transport = IoHttpTransport(
        timeout: const Duration(seconds: 3),
      );
      addTearDown(transport.close);

      // Act
      final TransportOutcome outcome = await transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('http://127.0.0.1:${raw.port}/x'),
        ),
      );

      // Assert
      expect(outcome, isA<NetworkFailure>());
      expect((outcome as NetworkFailure).reason, startsWith('http: '));
      expect(outcome.cause, isNotNull);
    });
  });
}
