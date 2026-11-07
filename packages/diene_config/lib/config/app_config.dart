/// Drop-in import for apps moving off an in-app `config/app_config.dart`.
library;

import 'package:diene_result/diene_result.dart';

import '../diene_config.dart';

export '../diene_config.dart';

/// A process-wide holder for the loaded configuration.
abstract final class AppConfig {
  static DieneConfig? _instance;

  static bool get isInstalled => _instance != null;

  /// Throws [StateError] before [install].
  static DieneConfig get instance {
    final DieneConfig? installed = _instance;
    if (installed == null) {
      throw StateError(
        'AppConfig.instance was read before install(); call '
        'AppConfig.install(config) once during startup.',
      );
    }
    return installed;
  }

  static Option<DieneConfig> get maybeInstance =>
      Option<DieneConfig>.fromNullable(_instance);

  /// Throws [StateError] on a second install unless [force] is set.
  static void install(DieneConfig config, {bool force = false}) {
    if (_instance != null && !force) {
      throw StateError(
        'AppConfig is already installed; pass force: true to replace it.',
      );
    }
    _instance = config;
  }

  /// Installs only on success.
  static Future<Result<DieneConfig>> loadAndInstall(
    ConfigLoader loader, {
    bool force = false,
  }) async {
    final Result<DieneConfig> loaded = await loader.load();
    return loaded.run((DieneConfig config) => install(config, force: force));
  }

  static void reset() {
    _instance = null;
  }
}
