import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Keeps the exact protected route, path and query, across login.
///
/// Only single-slash relative targets pass; anything else is an open redirect.
abstract final class ReturnTo {
  static const String queryKey = 'returnTo';

  /// Validates [target] and returns its `path[?query][#fragment]` text.
  static Result<String> capture(Uri target) {
    if (target.hasScheme || target.hasAuthority) {
      return _reject('returnTo target must be relative (no scheme/authority)');
    }
    final String path = target.path;
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.startsWith('/\\')) {
      return _reject('returnTo path must begin with a single "/"');
    }
    return Ok<String>(_render(target));
  }

  /// Adds the validated target to [loginBase] as `returnTo`.
  static Result<Uri> buildLoginRedirect(Uri loginBase, Uri target) =>
      capture(target).map(
        (String encoded) => loginBase.replace(
          queryParameters: <String, String>{
            ...loginBase.queryParameters,
            queryKey: encoded,
          },
        ),
      );

  /// Re-validates a captured value and returns the exact target.
  static Result<Uri> resolve(String raw) {
    if (raw.isEmpty) {
      return _reject('returnTo is empty');
    }
    final Uri parsed;
    try {
      parsed = Uri.parse(raw);
    } on FormatException {
      return _reject('returnTo is not a valid URI reference');
    }
    if (parsed.hasScheme || parsed.hasAuthority) {
      return _reject('returnTo must not carry a scheme/authority');
    }
    if (!parsed.path.startsWith('/') ||
        parsed.path.startsWith('//') ||
        raw.startsWith('//') ||
        raw.startsWith('/\\')) {
      return _reject('returnTo must be a single-slash relative path');
    }
    return Ok<Uri>(Uri.parse(_render(parsed)));
  }

  /// The target from a callback URL, or [fallback] when absent or invalid.
  static Uri continueFrom(Uri callback, {required Uri fallback}) {
    final String? raw = callback.queryParameters[queryKey];
    if (raw == null) {
      return fallback;
    }
    return resolve(raw).unwrapOr(fallback);
  }

  static String _render(Uri target) {
    final String query = target.hasQuery ? '?${target.query}' : '';
    final String fragment = target.hasFragment ? '#${target.fragment}' : '';
    return '${target.path}$query$fragment';
  }

  static Result<R> _reject<R>(String detail) => Err<R>(
    Problem(
      type: 'urn:diene:problem:return-to',
      title: 'Invalid returnTo target',
      status: 400,
      detail: detail,
    ),
  );
}
