import 'dart:convert';

import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';
import 'package:dio/dio.dart';

import '../bridge.dart';
import '../transport.dart';

/// Folds a generated SDK call into `Result<T>`, classified like [toResult].
class ResultSdk {
  const ResultSdk();

  Future<Result<T>> call<T>(
    Future<T> Function() invoke, {
    String? endpoint,
  }) async {
    try {
      return Ok<T>(await invoke());
    } on DioException catch (error) {
      // The backend adapter carries a token failure as the Problem itself.
      final Object? cause = error.error;
      if (cause is Problem) {
        return Err<T>(cause);
      }
      final Response<Object?>? response = error.response;
      final TransportOutcome outcome = response != null
          ? Received(
              HttpResponse(
                status: response.statusCode ?? 0,
                body: _bodyString(response.data),
              ),
            )
          : NetworkFailure(error.message ?? error.type.name);
      return toResult<T>(
        outcome,
        decode: (Map<String, Object?> _) =>
            throw StateError('decode unreachable on SDK error path'),
        endpoint: endpoint,
      );
    } on Object catch (error) {
      return Err<T>(
        Problem(
          type: BridgeProblems.transportFailure,
          title: 'Transport failure',
          status: 503,
          detail: 'SDK call threw: $error',
          data: <String, Object?>{'endpoint': ?endpoint},
        ),
      );
    }
  }

  static String _bodyString(Object? data) => switch (data) {
    null => '',
    final String s => s,
    _ => jsonEncode(data),
  };
}
