library;

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'merge.dart';
import 'util_problem.dart';

Future<Result<String>> readVfsText(Vfs vfs, String path) => vfs.readText(path);

/// Creates missing parent directories.
Future<Result<void>> writeVfsText(Vfs vfs, String path, String contents) =>
    vfs.writeText(path, contents, createParents: true);

/// A missing path is `Ok(null)`; any other failure passes through.
Future<Result<String?>> readOptionalVfsText(Vfs vfs, String path) async {
  final Result<bool> present = await vfs.exists(path);
  switch (present) {
    case Err<bool>(problem: final Problem problem):
      return Err<String?>(problem);
    case Ok<bool>(value: final bool exists):
      if (!exists) {
        return const Ok<String?>(null);
      }
  }
  final Result<String> text = await vfs.readText(path);
  return text.map((String value) => value);
}

final class ConfigLayer {
  const ConfigLayer({
    required this.path,
    required this.parse,
    this.optional = false,
  });

  final String path;

  final Result<JsonObject> Function(String text) parse;

  final bool optional;
}

/// Reads and merges [layers] in order; stops at the first failure.
Future<Result<JsonObject>> loadConfigLayers(
  Vfs vfs,
  List<ConfigLayer> layers,
) async {
  final List<JsonObject> loaded = <JsonObject>[];
  for (final ConfigLayer layer in layers) {
    final String? text;
    if (layer.optional) {
      final Result<String?> optional = await readOptionalVfsText(
        vfs,
        layer.path,
      );
      switch (optional) {
        case Err<String?>(problem: final Problem problem):
          return Err<JsonObject>(problem);
        case Ok<String?>(value: final String? value):
          text = value;
      }
    } else {
      final Result<String> required = await vfs.readText(layer.path);
      switch (required) {
        case Err<String>(problem: final Problem problem):
          return Err<JsonObject>(problem);
        case Ok<String>(value: final String value):
          text = value;
      }
    }

    if (text == null) {
      continue;
    }

    final Result<JsonObject> parsed = layer.parse(text);
    switch (parsed) {
      case Err<JsonObject>(problem: final Problem problem):
        return Err<JsonObject>(problem);
      case Ok<JsonObject>(value: final JsonObject value):
        loaded.add(value);
    }
  }

  if (loaded.isEmpty) {
    return utilFailure<JsonObject>(
      util: UtilName.vfs,
      code: UtilErrorCode.invalidInput,
      operation: 'loadConfigLayers',
      message: 'no configuration layer was present',
      details: <String, Object?>{
        'paths': <String>[for (final ConfigLayer layer in layers) layer.path],
      },
    );
  }

  return Ok<JsonObject>(deepMergeAll(loaded));
}
