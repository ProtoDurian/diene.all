import 'dart:convert';
import 'dart:io' as io;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/src/generated/export.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Route = ({int status, String body, String contentType});
typedef _Seen = ({String backend, String path, String? authorization});

final Problem _conflict = problemFixture(
  type: 'urn:diene:problem:conflict',
  title: 'Conflict',
  status: 409,
  data: <String, Object?>{'entityType': 'user', 'id': 'u1'},
);
final Problem _missing = problemFixture(
  type: 'urn:diene:problem:entity_not_found',
  title: 'Not found',
  status: 404,
);

final Map<String, _Route> _routes = <String, _Route>{
  '/ok': (status: 200, body: '{"ok":true}', contentType: 'application/json'),
  '/problem': (
    status: 409,
    body: jsonEncode(_conflict.toJson()),
    contentType: 'application/problem+json',
  ),
  '/plain-json': (
    status: 422,
    body: '{"error":"bad"}',
    contentType: 'application/json',
  ),
  '/text': (status: 502, body: 'Bad Gateway', contentType: 'text/plain'),
  '/users/u1': (
    status: 200,
    body: '{"id":"u1","email":"u1@example.test"}',
    contentType: 'application/json',
  ),
  '/users/missing': (
    status: 404,
    body: jsonEncode(_missing.toJson()),
    contentType: 'application/problem+json',
  ),
};

_Route _route(String path) =>
    _routes[path] ?? (status: 404, body: 'no route', contentType: 'text/plain');

/// Two backends and a dead address, either faked or served for real.
abstract class _World {
  String get name;
  Uri get baseA;
  Uri get baseB;
  Uri get dead;
  HttpTransport get transport;
  List<_Seen> get seen;
  Future<void> start();
  Future<void> stop();
}

final class _FakeWorld implements _World {
  @override
  final String name = 'fake backends';
  @override
  final Uri baseA = Uri.parse('https://a.fake.test');
  @override
  final Uri baseB = Uri.parse('https://b.fake.test');
  @override
  final Uri dead = Uri.parse('https://dead.fake.test');

  late final FakeHttpTransport _transport = FakeHttpTransport((
    HttpRequest request,
  ) {
    final String host = request.url.host;
    if (host != baseA.host && host != baseB.host) {
      return networkFailure('unmapped host');
    }
    seen.add((
      backend: host == baseA.host ? 'a' : 'b',
      path: request.url.path,
      authorization: request.headers['Authorization'],
    ));
    final _Route route = _route(request.url.path);
    return Received(
      HttpResponse(
        status: route.status,
        headers: <String, String>{'content-type': route.contentType},
        body: route.body,
      ),
    );
  });

  @override
  HttpTransport get transport => _transport;

  @override
  final List<_Seen> seen = <_Seen>[];

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

final class _StubServerWorld implements _World {
  @override
  final String name = 'loopback stub server';
  @override
  late Uri baseA;
  @override
  late Uri baseB;
  @override
  late Uri dead;
  @override
  final List<_Seen> seen = <_Seen>[];
  final IoHttpTransport _transport = IoHttpTransport(
    timeout: const Duration(seconds: 5),
  );
  final List<io.HttpServer> _servers = <io.HttpServer>[];

  @override
  HttpTransport get transport => _transport;

  Future<Uri> _serve(String backend) async {
    final io.HttpServer server = await io.HttpServer.bind(
      io.InternetAddress.loopbackIPv4,
      0,
    );
    _servers.add(server);
    server.listen((io.HttpRequest request) async {
      seen.add((
        backend: backend,
        path: request.uri.path,
        authorization: request.headers.value('authorization'),
      ));
      final _Route route = _route(request.uri.path);
      request.response
        ..statusCode = route.status
        ..headers.contentType = io.ContentType.parse(route.contentType)
        ..write(route.body);
      await request.response.close();
    });
    return Uri.parse('http://127.0.0.1:${server.port}');
  }

  @override
  Future<void> start() async {
    baseA = await _serve('a');
    baseB = await _serve('b');
    final io.HttpServer closed = await io.HttpServer.bind(
      io.InternetAddress.loopbackIPv4,
      0,
    );
    dead = Uri.parse('http://127.0.0.1:${closed.port}');
    await closed.close(force: true);
  }

  @override
  Future<void> stop() async {
    _transport.close();
    for (final io.HttpServer server in _servers) {
      await server.close(force: true);
    }
  }
}

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'lithium',
  service: 'api',
  module: module,
);

ApiEngine _engine(_World world) => ApiEngine.fromConfig(
  ApiEngineConfig(
    backends: <BackendConfig>[
      BackendConfig(
        coordinate: _coord('a'),
        baseUrl: world.baseA,
        resourceName: 'a',
      ),
      BackendConfig(
        coordinate: _coord('b'),
        baseUrl: world.baseB,
        resourceName: 'b',
      ),
      BackendConfig(coordinate: _coord('dead'), baseUrl: world.dead),
    ],
    rescue: RescueConfig(
      enabled: false,
      issuer: Uri.parse('https://issuer.cluster.atomi.cloud'),
      catalogHosts: const <String>[],
      endpointSuffixAllowlist: const <String>[],
    ),
  ),
  auth: FakeAuth(<String, String>{
    'lithium/lapras/api/a': 'tok-a',
    'lithium/lapras/api/b': 'tok-b',
  }),
  transport: world.transport,
);

Map<String, Object?> _json(Map<String, Object?> json) => json;

Result<Object?> _mapped(Result<UserProfile> result) => switch (result) {
  Ok<UserProfile>(:final value) => Ok<Object?>(value.toJson()),
  Err<UserProfile>(:final problem) => Err<Object?>(problem),
};

Future<Result<Map<String, Object?>>> _send(_World world, Uri url) async =>
    toResult<Map<String, Object?>>(
      await world.transport.send(HttpRequest(method: HttpMethod.get, url: url)),
      decode: _json,
      endpoint: url.path,
    );

void _suite(_World world, Map<String, Result<Object?>> record) {
  group(world.name, () {
    setUpAll(world.start);
    tearDownAll(world.stop);

    test('2xx JSON is Ok', () async {
      // Arrange
      final Uri url = world.baseA.resolve('/ok');

      // Act
      final Result<Map<String, Object?>> result = await _send(world, url);

      // Assert
      expect(expectOk(result), <String, Object?>{'ok': true});
      record['ok'] = result;
    });

    test('a problem body is that problem, data included', () async {
      // Arrange
      final Uri url = world.baseA.resolve('/problem');

      // Act
      final Result<Map<String, Object?>> result = await _send(world, url);

      // Assert
      expect(expectProblemType(result, _conflict.type), _conflict);
      record['problem'] = result;
    });

    test('other JSON is an unexpected response with its status', () async {
      // Arrange
      final Uri url = world.baseA.resolve('/plain-json');

      // Act
      final Result<Map<String, Object?>> result = await _send(world, url);

      // Assert
      final Problem problem = expectProblemType(
        result,
        BridgeProblems.unexpectedResponse,
      );
      expect(problem.status, 422);
      expect(problem.data['body'], <String, Object?>{'error': 'bad'});
      record['plain-json'] = result;
    });

    test('a non-JSON error is a transport failure with a snippet', () async {
      // Arrange
      final Uri url = world.baseA.resolve('/text');

      // Act
      final Result<Map<String, Object?>> result = await _send(world, url);

      // Assert
      final Problem problem = expectProblemType(
        result,
        BridgeProblems.transportFailure,
      );
      expect(problem.status, 502);
      expect(problem.data['bodySnippet'], 'Bad Gateway');
      record['text'] = result;
    });

    test('an unreachable address is a transport failure', () async {
      // Arrange
      final Uri url = world.dead.resolve('/ok');

      // Act
      final Result<Map<String, Object?>> result = await _send(world, url);

      // Assert
      expect(
        expectProblemType(result, BridgeProblems.transportFailure).status,
        503,
      );
    });

    test('each backend call carries only its own token', () async {
      // Arrange
      final ApiEngine engine = _engine(world);
      world.seen.clear();

      // Act
      final Result<Map<String, Object?>> a = await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/ok',
            decode: _json,
          );
      final Result<Map<String, Object?>> b = await engine
          .backend(_coord('b'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/ok',
            decode: _json,
          );

      // Assert
      expectOk(a);
      expectOk(b);
      expect(world.seen, <_Seen>[
        (backend: 'a', path: '/ok', authorization: 'Bearer tok-a'),
        (backend: 'b', path: '/ok', authorization: 'Bearer tok-b'),
      ]);
    });

    test('a hard failure on a backend is an Err after the retry', () async {
      // Arrange
      final Backend backend = _engine(world).backend(_coord('dead'))!;

      // Act
      final Result<Map<String, Object?>> result = await backend
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/ok',
            decode: _json,
          );

      // Assert
      expectProblemType(result, BridgeProblems.transportFailure);
    });

    test('the generated client decodes a 2xx into its model', () async {
      // Arrange
      final ServiceSdk sdk = _engine(
        world,
      ).backend(_coord('a'))!.sdk(ServiceSdk.new);

      // Act
      final Result<UserProfile> result = await const ResultSdk().call(
        () => sdk.users.getUser(id: 'u1'),
      );

      // Assert
      expect(expectOk(result).email, 'u1@example.test');
      record['sdk-ok'] = _mapped(result);
    });

    test(
      'the generated client turns a problem body into that problem',
      () async {
        // Arrange
        final ServiceSdk sdk = _engine(
          world,
        ).backend(_coord('b'))!.sdk(ServiceSdk.new);

        // Act
        final Result<UserProfile> result = await const ResultSdk().call(
          () => sdk.users.getUser(id: 'missing'),
        );

        // Assert
        expect(expectProblemType(result, _missing.type), _missing);
        record['sdk-problem'] = _mapped(result);
      },
    );
  });
}

void main() {
  final Map<String, Result<Object?>> fake = <String, Result<Object?>>{};
  final Map<String, Result<Object?>> real = <String, Result<Object?>>{};

  _suite(_FakeWorld(), fake);
  _suite(_StubServerWorld(), real);

  test('the fakes give the same results as the stub server', () {
    // Arrange
    String render(Result<Object?> r) => jsonEncode(switch (r) {
      Ok<Object?>(:final value) => <String, Object?>{'ok': value},
      Err<Object?>(:final problem) => <String, Object?>{
        'err': problem.toJson(),
      },
    });

    // Act
    final Map<String, String> fakeOut = fake.map(
      (String k, Result<Object?> v) => MapEntry(k, render(v)),
    );
    final Map<String, String> realOut = real.map(
      (String k, Result<Object?> v) => MapEntry(k, render(v)),
    );

    // Assert
    expect(fakeOut.keys, hasLength(6));
    expect(realOut, fakeOut);
  });
}
