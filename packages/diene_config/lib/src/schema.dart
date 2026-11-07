import 'dart:collection';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_result/diene_result.dart';

import 'config_problem.dart';

/// Type-erased view of a [ConfigBlock], so differently typed blocks compose.
abstract interface class ConfigBlockSchema {
  String get key;

  bool get required;

  Object? decodeUntyped(Map<String, Object?> value);
}

/// One engine- or service-owned block; a throw from [decode] becomes a
/// `schema_invalid` error.
final class ConfigBlock<T> implements ConfigBlockSchema {
  const ConfigBlock({
    required this.key,
    required this.decode,
    this.required = true,
  });

  @override
  final String key;

  final T Function(Map<String, Object?> values) decode;

  @override
  final bool required;

  @override
  Object? decodeUntyped(Map<String, Object?> value) => decode(value);
}

/// The root schema a service composes from engine-owned blocks and its own.
final class ConfigSchema {
  /// Throws [ArgumentError] on an empty, reserved or duplicate block key.
  ConfigSchema({
    required Iterable<ConfigBlockSchema> blocks,
    this.rejectUnknownBlocks = true,
  }) : _blocks = List<ConfigBlockSchema>.unmodifiable(blocks) {
    _validateBlockKeys();
  }

  final List<ConfigBlockSchema> _blocks;

  /// Whether a root key with no composed block is an error.
  final bool rejectUnknownBlocks;

  List<ConfigBlockSchema> get blocks => _blocks;

  /// Validates the final merged tree, collecting every error in one problem.
  Result<DieneConfig> validate(Map<String, Object?> values) {
    final Map<String, String> actualKeys = <String, String>{};
    final List<String> errors = <String>[];

    for (final String key in values.keys) {
      if (key == _schemaKey) {
        continue;
      }
      final String canonical = canonicalConfigKey(key);
      final String? existing = actualKeys[canonical];
      if (existing != null) {
        errors.add('root keys $existing and $key collide');
      } else {
        actualKeys[canonical] = key;
      }
    }

    final Map<ConfigBlockSchema, Object?> decoded =
        LinkedHashMap<ConfigBlockSchema, Object?>.identity();
    final Set<String> declared = <String>{};
    for (final ConfigBlockSchema block in _blocks) {
      final String canonical = canonicalConfigKey(block.key);
      declared.add(canonical);
      final String? actual = actualKeys[canonical];
      if (actual == null) {
        if (block.required) {
          errors.add('${block.key}: required block is missing');
        }
        continue;
      }
      final Object? raw = values[actual];
      if (raw is! Map<String, Object?>) {
        errors.add('${block.key}: block must be a map');
        continue;
      }
      try {
        decoded[block] = block.decodeUntyped(raw);
      } on Object catch (error) {
        errors.add('${block.key}: $error');
      }
    }

    if (rejectUnknownBlocks) {
      for (final MapEntry<String, String> entry in actualKeys.entries) {
        if (!declared.contains(entry.key)) {
          errors.add('${entry.value}: no composed block schema');
        }
      }
    }

    if (errors.isNotEmpty) {
      return configFailure<DieneConfig>(
        code: ConfigProblemCode.schemaInvalid,
        message: 'final configuration failed validation',
        details: <String, Object?>{'errors': List<String>.unmodifiable(errors)},
      );
    }
    return Ok<DieneConfig>(
      DieneConfig._(
        _freezeMap(values),
        UnmodifiableMapView<ConfigBlockSchema, Object?>(decoded),
      ),
    );
  }

  void _validateBlockKeys() {
    final Set<String> seen = <String>{};
    for (final ConfigBlockSchema block in _blocks) {
      if (block.key.isEmpty || block.key == _schemaKey) {
        throw ArgumentError.value(block.key, 'blocks', 'invalid block key');
      }
      if (!seen.add(canonicalConfigKey(block.key))) {
        throw ArgumentError.value(block.key, 'blocks', 'duplicate block key');
      }
    }
  }
}

/// An immutable, validated configuration and its typed slices.
final class DieneConfig {
  const DieneConfig._(this.raw, this._decoded);

  /// The final merged tree, deeply unmodifiable.
  final Map<String, Object?> raw;

  // Keyed by block identity: a same-key block that was not composed has no slice.
  final Map<ConfigBlockSchema, Object?> _decoded;

  /// Throws [StateError] when [block] was not composed or is absent.
  T slice<T>(ConfigBlock<T> block) {
    if (!_decoded.containsKey(block)) {
      throw StateError('Configuration block ${block.key} was not composed');
    }
    return _decoded[block] as T;
  }

  bool hasSlice(ConfigBlockSchema block) => _decoded.containsKey(block);

  Option<T> optionalSlice<T>(ConfigBlock<T> block) =>
      hasSlice(block) ? Some<T>(slice<T>(block)) : None<T>();

  /// An untyped block of [raw], matched ignoring case and separators.
  Result<Map<String, Object?>> rawSlice(String key) {
    final String canonical = canonicalConfigKey(key);
    for (final MapEntry<String, Object?> entry in raw.entries) {
      if (canonicalConfigKey(entry.key) != canonical) {
        continue;
      }
      final Object? value = entry.value;
      if (value is! Map<String, Object?>) {
        return configFailure<Map<String, Object?>>(
          code: ConfigProblemCode.schemaInvalid,
          message: 'configuration block $key is not a map',
          details: <String, Object?>{'block': key},
        );
      }
      return Ok<Map<String, Object?>>(value);
    }
    return configFailure<Map<String, Object?>>(
      code: ConfigProblemCode.schemaInvalid,
      message: 'configuration block $key was not loaded',
      details: <String, Object?>{'block': key},
    );
  }

  /// [raw] with sorted keys at every depth.
  Result<Object?> stableProjection() => stableConfig(raw);
}

const String _schemaKey = r'$schema';

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    UnmodifiableMapView<String, Object?>(
      value.map(
        (String key, Object? item) =>
            MapEntry<String, Object?>(key, _freeze(item)),
      ),
    );

Object? _freeze(Object? value) => switch (value) {
  final Map<String, Object?> map => _freezeMap(map),
  final List<Object?> list => List<Object?>.unmodifiable(list.map(_freeze)),
  _ => value,
};
