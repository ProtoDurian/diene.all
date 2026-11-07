library;

import 'dart:convert';

import 'package:diene_api_engine/diene_api_engine.dart';
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

ApiEngine _engine(HttpTransport transport, {IAuth? auth, String? resource}) =>
    ApiEngine.fromConfig(
      ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://primary.example.com'),
            resourceName: resource,
          ),
        ],
        rescue: _disabledRescue(),
      ),
      auth: auth,
      transport: transport,
    );

Dio _dio(ApiEngine engine) {
  final Backend backend = engine.backend(_coord('a'))!;
  return Dio(BaseOptions(baseUrl: backend.config.baseUrl.toString()))
    ..httpClientAdapter = BackendClientAdapter(backend);
}

void main() {
  group('BackendClientAdapter drives the production pipeline', () {
    test(
      'a received response is returned to dio with status and body',
      () async {
        // Arrange
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest _) => okJson(<String, Object?>{'who': 'a'}),
        );

        // Act
        final Response<Object?> response = await _dio(
          _engine(transport),
        ).get<Object?>('/users/42');

        // Assert
        expect(response.statusCode, 200);

        expect(response.data, isA<Map<String, dynamic>>());
        expect((response.data! as Map<String, dynamic>)['who'], 'a');

        expect(transport.sent, hasLength(1));
        expect(transport.sent.single.url.path, '/users/42');
      },
    );

    test('dio request HEADERS reach the transport, stringified', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      // Act
      await _dio(_engine(transport)).get<Object?>(
        '/thing',
        options: Options(
          headers: <String, Object?>{'x-trace': 'abc', 'x-attempt': 2},
        ),
      );

      // Assert
      final HttpRequest sent = transport.sent.single;
      expect(sent.headers['x-trace'], 'abc');
      expect(sent.headers['x-attempt'], '2', reason: 'coerced to String');
    });

    test('a MAP body is JSON-encoded on the way through', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      // Act
      await _dio(
        _engine(transport),
      ).post<Object?>('/thing', data: <String, Object?>{'a': 1});

      // Assert
      expect(jsonDecode(transport.sent.single.body!), <String, Object?>{
        'a': 1,
      });
    });

    test('a STRING body is passed through unchanged', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      // Act
      await _dio(_engine(transport)).post<Object?>(
        '/thing',
        data: '{"raw":true}',
        options: Options(contentType: Headers.jsonContentType),
      );

      // Assert
      expect(transport.sent.single.body, '{"raw":true}');
    });

    test('query parameters survive the round trip', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      // Act
      await _dio(
        _engine(transport),
      ).get<Object?>('/thing', queryParameters: <String, Object?>{'page': 2});

      // Assert
      expect(transport.sent.single.url.queryParameters['page'], '2');
    });

    test('a HARD network failure becomes a dio connectionError', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => networkFailure('primary refused'),
      );

      // Act
      // Assert
      await expectLater(
        _dio(_engine(transport)).get<Object?>('/thing'),
        throwsA(
          isA<DioException>().having(
            (DioException e) => '${e.message} ${e.error}',
            'reason',
            contains('primary refused'),
          ),
        ),
      );
    });

    test('a TOKEN failure becomes a dio error carrying the Problem', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      final ApiEngine engine = _engine(
        transport,
        auth: FakeAuth(const <String, String>{}),
        resource: 'a',
      );

      // Act
      try {
        await _dio(engine).get<Object?>('/thing');

        // Assert
        fail('expected a DioException carrying the auth Problem');
      } on DioException catch (error) {
        expect(error.error, isA<Problem>());
        expect((error.error! as Problem).status, 401);
      }

      expect(transport.sent, isEmpty);
    });

    test('an error status is returned as a response, not thrown', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => Received(
          HttpResponse(
            status: 404,
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(<String, Object?>{'type': 'urn:x', 'status': 404}),
          ),
        ),
      );

      // Act
      final Response<Object?> response = await _dio(_engine(transport))
          .get<Object?>(
            '/missing',
            options: Options(validateStatus: (int? _) => true),
          );

      // Assert
      expect(response.statusCode, 404);
    });

    test('close is a no-op and does not throw', () {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );
      final BackendClientAdapter adapter = BackendClientAdapter(
        _engine(transport).backend(_coord('a'))!,
      );

      // Act
      // Assert
      expect(adapter.close, returnsNormally);
      expect(() => adapter.close(force: true), returnsNormally);
    });
  });

  group('Backend.sdk wires a generated client through the adapter', () {
    test('the Dio handed to the factory is backed by this backend', () async {
      // Arrange
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'via': 'sdk'}),
      );
      final Backend backend = _engine(transport).backend(_coord('a'))!;

      // Act
      final Dio dio = backend.sdk<Dio>((Dio d) => d);
      final Response<Object?> response = await dio.get<Object?>('/sdk');

      // Assert
      expect(response.statusCode, 200);
      expect(transport.sent.single.url.path, '/sdk');
    });
  });

  group('adapter body fallbacks when there is NO request stream', () {
    Future<ResponseBody> fetchWith(Object? data, FakeHttpTransport t) {
      final BackendClientAdapter adapter = BackendClientAdapter(
        _engine(t).backend(_coord('a'))!,
      );
      return adapter.fetch(
        RequestOptions(path: '/thing', method: 'POST', data: data),
        null,
        null,
      );
    }

    test('a STRING data payload is passed through unchanged', () async {
      // Arrange
      final FakeHttpTransport t = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      // Act
      await fetchWith('{"raw":true}', t);

      // Assert
      expect(t.sent.single.body, '{"raw":true}');
    });

    test('a NON-string data payload is JSON-encoded', () async {
      // Arrange
      final FakeHttpTransport t = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      // Act
      await fetchWith(<String, Object?>{'a': 1}, t);

      // Assert
      expect(jsonDecode(t.sent.single.body!), <String, Object?>{'a': 1});
    });

    test('a null data payload sends no body at all', () async {
      // Arrange
      final FakeHttpTransport t = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      // Act
      await fetchWith(null, t);

      // Assert
      expect(t.sent.single.body, isNull);
    });
  });
}
