import 'dart:convert';

import 'package:diene_problems/diene_problems.dart'
    show ErrorPortal, Problem, problemTypeUri;
import 'package:diene_result/diene_result.dart';

import 'transport.dart';

/// The engine's own problem type URIs, built by `diene_problems`.
abstract class BridgeProblems {
  /// The portal the type URIs are built under; local by default.
  static ErrorPortal portal = ErrorPortal.localError;

  static String _uri(String id) =>
      problemTypeUri(portal: portal, version: 'v1', id: id);

  // Ids are snake_case: the problem id pattern rejects a hyphen.
  static String get transportFailure => _uri('transport_failure');
  static String get unexpectedResponse => _uri('unexpected_response');
  static String get duplicateBackend => _uri('duplicate_backend');
  static String get authTokenUnavailable => _uri('auth_token_unavailable');
}

/// True when [value] has a string `type` and an int `status`.
bool isProblemJson(Object? value) =>
    value is Map<String, Object?> &&
    value['type'] is String &&
    value['status'] is int;

/// [body] as a JSON object, or null when it is not one.
Map<String, Object?>? tryDecodeObject(String body) {
  if (body.trim().isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(body);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Folds a [TransportOutcome] into a `Result<T>`; it never throws.
///
/// * [NetworkFailure] → transport failure.
/// * 2xx JSON object → `Ok(decode(json))`; non-JSON or a failed decode →
///   transport failure.
/// * non-2xx problem body → that `Problem`, `data` included.
/// * non-2xx other JSON → unexpected response, status and body kept.
/// * non-2xx non-JSON → transport failure with status and body snippet.
Result<T> toResult<T>(
  TransportOutcome outcome, {
  required T Function(Map<String, Object?> json) decode,
  String? endpoint,
}) {
  switch (outcome) {
    case NetworkFailure(:final reason):
      return Err<T>(
        Problem(
          type: BridgeProblems.transportFailure,
          title: 'Transport failure',
          status: 503,
          detail: reason,
          data: <String, Object?>{'endpoint': ?endpoint, 'reason': reason},
        ),
      );
    case Received(:final response):
      return _fromResponse<T>(response, decode: decode, endpoint: endpoint);
  }
}

Result<T> _fromResponse<T>(
  HttpResponse response, {
  required T Function(Map<String, Object?> json) decode,
  String? endpoint,
}) {
  final bool ok = response.status >= 200 && response.status < 300;
  final Map<String, Object?>? json = tryDecodeObject(response.body);

  if (ok) {
    if (json == null) {
      return Err<T>(
        _transport('success body was not a JSON object', response, endpoint),
      );
    }
    try {
      return Ok<T>(decode(json));
    } on Object catch (error) {
      return Err<T>(_transport('decode failed: $error', response, endpoint));
    }
  }

  final Problem? problem = isProblemJson(json) ? _problemOrNull(json!) : null;
  if (problem != null) {
    return Err<T>(problem);
  }
  if (json != null) {
    return Err<T>(
      Problem(
        type: BridgeProblems.unexpectedResponse,
        title: 'Unexpected service response',
        status: response.status,
        detail: 'Non-problem JSON body',
        instance: endpoint,
        data: <String, Object?>{
          'endpoint': ?endpoint,
          'upstreamStatus': response.status,
          'body': json,
        },
      ),
    );
  }
  return Err<T>(_transport('non-JSON error body', response, endpoint));
}

Problem? _problemOrNull(Map<String, Object?> json) {
  try {
    return Problem.fromJson(json);
  } on Object {
    return null;
  }
}

Problem _transport(String reason, HttpResponse response, String? endpoint) {
  final String snippet = response.body.length > 256
      ? '${response.body.substring(0, 256)}…'
      : response.body;
  return Problem(
    type: BridgeProblems.transportFailure,
    title: 'Transport failure',
    status: response.status == 0 ? 503 : response.status,
    detail: reason,
    instance: endpoint,
    data: <String, Object?>{
      'endpoint': ?endpoint,
      'reason': reason,
      'upstreamStatus': response.status,
      if (snippet.isNotEmpty) 'bodySnippet': snippet,
    },
  );
}
