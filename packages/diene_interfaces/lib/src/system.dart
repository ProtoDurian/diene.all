import 'package:diene_result/diene_result.dart';

/// The process's own environment, working directory and clock.
abstract interface class System {
  /// An unset variable is `Ok(null)`, not a failure.
  Result<String?> environment(String name);

  Result<String> currentDirectory();

  Result<DateTime> nowUtc();

  Future<Result<void>> delay(Duration duration);
}
