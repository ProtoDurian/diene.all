import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// HTTP verbs the engine carries to the transport.
enum HttpMethod { get, post, put, patch, delete, head }

/// A transport-level request with its base URL and auth header already set.
@immutable
class HttpRequest {
  const HttpRequest({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body,
  });

  final HttpMethod method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;

  HttpRequest withUrl(Uri url) =>
      HttpRequest(method: method, url: url, headers: headers, body: body);
}

/// A received HTTP response of any status; never a network failure.
@immutable
class HttpResponse {
  const HttpResponse({
    required this.status,
    this.headers = const <String, String>{},
    this.body = '',
  });

  final int status;
  final Map<String, String> headers;
  final String body;
}

/// What a send returns: a [Received] response or a [NetworkFailure].
@immutable
sealed class TransportOutcome {
  const TransportOutcome();
}

/// Any HTTP status was received.
@immutable
final class Received extends TransportOutcome {
  const Received(this.response);

  final HttpResponse response;
}

/// No HTTP status was received: refused, reset, DNS, TLS or timeout.
@immutable
final class NetworkFailure extends TransportOutcome {
  const NetworkFailure(this.reason, {this.cause});

  final String reason;
  final Object? cause;
}

/// The transport seam; implementations return failures and never throw.
abstract interface class HttpTransport {
  Future<TransportOutcome> send(HttpRequest request);
}

/// Retries exactly once on a [NetworkFailure]; a received status is final.
final class RetryOnceTransport implements HttpTransport {
  const RetryOnceTransport(this._inner);

  final HttpTransport _inner;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    final TransportOutcome first = await _inner.send(request);
    if (first is Received) {
      return first;
    }
    return _inner.send(request);
  }
}

/// A `dart:io` [HttpClient] transport.
final class IoHttpTransport implements HttpTransport {
  IoHttpTransport({Duration? timeout, HttpClient? client})
    : _timeout = timeout ?? const Duration(seconds: 30),
      _client = client ?? HttpClient();

  final Duration _timeout;
  final HttpClient _client;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    try {
      final HttpClientRequest req = await _client
          .openUrl(_verb(request.method), request.url)
          .timeout(_timeout);
      request.headers.forEach(req.headers.set);
      final String? body = request.body;
      if (body != null) {
        req.write(body);
      }
      final HttpClientResponse res = await req.close().timeout(_timeout);
      final String payload = await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(_timeout);
      final Map<String, String> headers = <String, String>{};
      res.headers.forEach((String name, List<String> values) {
        headers[name] = values.join(', ');
      });
      return Received(
        HttpResponse(status: res.statusCode, headers: headers, body: payload),
      );
    } on SocketException catch (error) {
      return NetworkFailure('socket: ${error.message}', cause: error);
    } on HandshakeException catch (error) {
      return NetworkFailure('tls: ${error.message}', cause: error);
    } on TimeoutException catch (error) {
      return NetworkFailure('timeout', cause: error);
    } on HttpException catch (error) {
      return NetworkFailure('http: ${error.message}', cause: error);
    }
  }

  void close() => _client.close(force: true);

  String _verb(HttpMethod method) => switch (method) {
    HttpMethod.get => 'GET',
    HttpMethod.post => 'POST',
    HttpMethod.put => 'PUT',
    HttpMethod.patch => 'PATCH',
    HttpMethod.delete => 'DELETE',
    HttpMethod.head => 'HEAD',
  };
}
