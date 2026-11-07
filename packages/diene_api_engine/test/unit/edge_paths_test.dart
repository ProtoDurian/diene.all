library;

import 'dart:convert';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: module,
);

Map<String, Object?> _id(Map<String, Object?> json) => json;

void main() {
  group('bridge edge cases', () {
    test('an error body over 256 bytes is TRUNCATED with an ellipsis', () {
      // Arrange
      final String huge = 'x' * 900;

      // Act
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(HttpResponse(status: 502, body: huge)),
            decode: _id,
            endpoint: '/thing',
          );

      // Assert
      final String snippet = expectErr(result).data['bodySnippet']! as String;
      expect(snippet.length, lessThan(huge.length));
      expect(snippet.endsWith('…'), isTrue);
      expect(snippet.substring(0, 256), 'x' * 256);
    });

    test('a short error body is carried WHOLE, with no ellipsis', () {
      // Arrange
      // Act
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(const HttpResponse(status: 502, body: 'Bad Gateway')),
            decode: _id,
            endpoint: '/thing',
          );

      // Assert
      expect(expectErr(result).data['bodySnippet'], 'Bad Gateway');
    });

    test('a problem body MISSING title still decodes, with defaults', () {
      // Arrange
      // Act
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(
              HttpResponse(
                status: 400,
                body: jsonEncode(<String, Object?>{
                  'type': 'urn:example:problem',
                  'status': 400,
                  'data': <String, Object?>{'k': 'v'},
                }),
              ),
            ),
            decode: _id,
            endpoint: '/thing',
          );

      // Assert
      final Problem got = expectErr(result);
      expect(got.type, 'urn:example:problem');
      expect(got.status, 400);
      expect(got.title, 'Unexpected problem', reason: 'the defaulted title');
      expect(got.data['k'], 'v', reason: 'the data extension survives');
    });

    test('a transport failure with NO endpoint omits the endpoint key', () {
      // Arrange
      // Act
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(networkFailure('down'), decode: _id);

      // Assert
      expect(expectErr(result).data.containsKey('endpoint'), isFalse);
    });
  });

  group('rescue router jitter and document handling', () {
    RescueConfig config({
      Duration maxJitter = const Duration(milliseconds: 40),
    }) => RescueConfig(
      enabled: true,
      issuer: Uri.parse('https://auth.example.com'),
      catalogHosts: const <String>['https://seed.example.com'],
      endpointSuffixAllowlist: const <String>['.example.com'],
      maxJitter: maxJitter,
    );

    test('production jitter stays within [0, maxJitter]', () {
      // Arrange
      final RescueRouter router = RescueRouter(
        config: config(),
        store: FakeRescueStore(),
        transport: FakeHttpTransport((HttpRequest _) => networkFailure()),
        sleep: noSleep,
        nowMs: FakeClock().nowMs,
      );

      // Act
      for (int i = 0; i < 50; i += 1) {
        final Duration drawn = router.nextJitter();

        // Assert
        expect(drawn, greaterThanOrEqualTo(Duration.zero));
        expect(drawn, lessThanOrEqualTo(const Duration(milliseconds: 40)));
      }
    });

    test('a zero maxJitter yields exactly zero, never a random draw', () {
      // Arrange
      final RescueRouter router = RescueRouter(
        config: config(maxJitter: Duration.zero),
        store: FakeRescueStore(),
        transport: FakeHttpTransport((HttpRequest _) => networkFailure()),
        sleep: noSleep,
        nowMs: FakeClock().nowMs,
      );

      // Act
      // Assert
      expect(router.nextJitter(), Duration.zero);
    });

    test('a MALFORMED cached document is ignored rather than thrown', () {
      // Arrange
      // Act
      // Assert
      expect(DocC.tryDecode('{not json at all'), isNull);
      expect(DocC.tryDecode('[]'), isNull);
    });
  });

  group('DocA encoding', () {
    test('round-trips through toJson', () {
      // Arrange
      const DocA doc = DocA(
        version: 7,
        catalogHosts: <String>['https://a.example.com'],
      );

      // Act
      final Map<String, Object?> json = doc.toJson();

      // Assert
      expect(json['version'], 7);
      expect(json['catalogHosts'], <String>['https://a.example.com']);
      expect(DocA.fromJson(json).version, 7);
      expect(DocA.fromJson(json).catalogHosts, doc.catalogHosts);
    });
  });

  group('client tree enumeration', () {
    test('backends exposes every registered BackendConfig', () {
      // Arrange
      final ClientTree tree = ClientTree();
      final BackendConfig a = BackendConfig(
        coordinate: _coord('a'),
        baseUrl: Uri.parse('https://a.example.com'),
      );
      final BackendConfig b = BackendConfig(
        coordinate: _coord('b'),
        baseUrl: Uri.parse('https://b.example.com'),
      );

      // Act
      // Assert
      expect(tree.register(a).isOk, isTrue);
      expect(tree.register(b).isOk, isTrue);

      expect(tree.backends, hasLength(2));
      expect(
        tree.backends.map((BackendConfig c) => c.coordinate.module).toSet(),
        <String>{'a', 'b'},
      );
    });
  });
}
