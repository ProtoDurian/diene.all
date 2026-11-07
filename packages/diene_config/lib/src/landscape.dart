import 'package:diene_result/diene_result.dart';

import 'config_problem.dart';

const String landscapeDefineKey = 'DIENE_LANDSCAPE';

/// Supplies the build-time landscape identity.
abstract interface class LandscapeSource {
  /// Returns the raw, untrimmed value.
  String read();
}

/// Reads `--dart-define=DIENE_LANDSCAPE=<track>`, or an explicit [value].
final class DartDefineLandscapeSource implements LandscapeSource {
  const DartDefineLandscapeSource({
    this.value = const String.fromEnvironment(landscapeDefineKey),
  });

  final String value;

  @override
  String read() => value;
}

/// Returns the injected landscape; a blank value is `landscape_missing`.
Result<String> landscape({
  LandscapeSource source = const DartDefineLandscapeSource(),
}) {
  final String value = source.read().trim();
  if (value.isEmpty) {
    return configFailure<String>(
      code: ConfigProblemCode.landscapeMissing,
      message:
          'no landscape identity; build with '
          '--dart-define=$landscapeDefineKey=<track>',
      details: <String, Object?>{'define': landscapeDefineKey},
    );
  }
  return Ok<String>(value);
}
