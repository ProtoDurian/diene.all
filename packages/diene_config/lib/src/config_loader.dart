import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'config_source.dart';
import 'schema.dart';

/// Enumerated `--dart-define` values, applied as the last layer.
final class DartDefineOverrides {
  const DartDefineOverrides({
    required this.prefix,
    this.values = const <String, String>{},
  });

  /// Matched ignoring case.
  final String prefix;

  final Map<String, String> values;

  /// A rejected key returns the `diene_core_utils` problem unchanged.
  Result<JsonObject> layer() => environmentToNestedMap(values, prefix: prefix);
}

/// Loads base, overlay, development override and defines, in that order, then
/// validates the merged tree once.
final class ConfigLoader {
  const ConfigLoader({
    required this.base,
    required this.schema,
    required this.dartDefines,
    this.overlay,
    this.developmentOverride,
  });

  final ConfigSource base;

  /// The flavor or landscape layer.
  final ConfigSource? overlay;

  /// Applied after [overlay] and before [dartDefines].
  final ConfigSource? developmentOverride;

  final DartDefineOverrides dartDefines;

  final ConfigSchema schema;

  /// Never throws for an expected failure; it returns an `Err`.
  Future<Result<DieneConfig>> load() async {
    final List<JsonObject> layers = <JsonObject>[];

    for (final ConfigSource? source in <ConfigSource?>[
      base,
      overlay,
      developmentOverride,
    ]) {
      if (source == null) {
        continue;
      }
      switch (await source.load()) {
        case Ok<JsonObject>(value: final JsonObject layer):
          layers.add(layer);
        case Err<JsonObject>(problem: final Problem problem):
          return Err<DieneConfig>(problem);
      }
    }

    switch (dartDefines.layer()) {
      case Ok<JsonObject>(value: final JsonObject defines):
        layers.add(defines);
      case Err<JsonObject>(problem: final Problem problem):
        return Err<DieneConfig>(problem);
    }

    return schema.validate(deepMergeAll(layers));
  }
}
