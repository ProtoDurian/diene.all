library;

import 'package:diene_result/diene_result.dart';

import 'merge.dart';
import 'util_problem.dart';

bool isJsonObject(Object? value) => value is Map<String, Object?>;

/// Clones with keys sorted at every depth; a cycle is `record_unprojectable`.
Result<Object?> stableConfig(Object? value) {
  try {
    return Ok<Object?>(_project(value, <Object>[], '<root>'));
  } on _CycleDetected catch (cycle) {
    return utilFailure<Object?>(
      util: UtilName.record,
      code: UtilErrorCode.unprojectable,
      operation: 'stableConfig',
      message: 'value contains a circular reference',
      details: <String, Object?>{'path': cycle.path},
    );
  }
}

final class _CycleDetected implements Exception {
  const _CycleDetected(this.path);

  final String path;
}

Object? _project(Object? value, List<Object> ancestors, String path) {
  if (value is Map<String, Object?>) {
    _guardCycle(value, ancestors, path);
    final List<String> keys = value.keys.toList()..sort();
    final List<Object> nested = <Object>[...ancestors, value];
    return <String, Object?>{
      for (final String key in keys)
        key: _project(value[key], nested, '$path.$key'),
    };
  }
  if (value is List<Object?>) {
    _guardCycle(value, ancestors, path);
    final List<Object> nested = <Object>[...ancestors, value];
    return <Object?>[
      for (int index = 0; index < value.length; index += 1)
        _project(value[index], nested, '$path[$index]'),
    ];
  }
  return value;
}

void _guardCycle(Object node, List<Object> ancestors, String path) {
  for (final Object ancestor in ancestors) {
    if (identical(ancestor, node)) {
      throw _CycleDetected(path);
    }
  }
}

Result<JsonObject> stableConfigObject(JsonObject value) =>
    stableConfig(value).map((Object? projected) => projected! as JsonObject);
