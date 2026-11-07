import 'dart:async';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_result/diene_result.dart';
import 'package:yaml/yaml.dart';

import 'config_problem.dart';

/// Supplies one configuration layer.
abstract interface class ConfigSource {
  Future<Result<JsonObject>> load();
}

/// Reads a YAML layer through an injected text callback.
final class YamlConfigSource implements ConfigSource {
  /// [name] labels the layer in failures; the source never opens it as a path.
  const YamlConfigSource({required this.read, required this.name});

  factory YamlConfigSource.string(String document, {String name = 'memory'}) =>
      YamlConfigSource(read: () => document, name: name);

  final FutureOr<String> Function() read;

  final String name;

  @override
  Future<Result<JsonObject>> load() async {
    final Object? document;
    try {
      document = loadYaml(await read());
    } on Object catch (error) {
      return configFailure<JsonObject>(
        code: ConfigProblemCode.sourceUnreadable,
        message: 'configuration layer $name could not be read',
        details: <String, Object?>{'source': name, 'reason': '$error'},
      );
    }

    if (document == null) {
      return Ok<JsonObject>(<String, Object?>{});
    }
    if (document is! Map<Object?, Object?>) {
      return configFailure<JsonObject>(
        code: ConfigProblemCode.sourceNotAMap,
        message: 'configuration layer $name must have a map at its root',
        details: <String, Object?>{'source': name},
      );
    }
    return Ok<JsonObject>(_plainMap(document));
  }

  // YamlMap is not a Map<String, Object?>, so deepMerge would replace it whole.
  JsonObject _plainMap(Map<Object?, Object?> value) => value.map(
    (Object? key, Object? item) =>
        MapEntry<String, Object?>(key.toString(), _plainValue(item)),
  );

  Object? _plainValue(Object? value) => switch (value) {
    final Map<Object?, Object?> map => _plainMap(map),
    final List<Object?> list =>
      list.map<Object?>(_plainValue).toList(growable: false),
    _ => value,
  };
}
