library;

typedef JsonObject = Map<String, Object?>;

Object? deepClone(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in value.entries)
        entry.key: deepClone(entry.value),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final Object? item in value) deepClone(item)];
  }
  return value;
}

/// Keys match ignoring case, `-` and `_`; first spelling wins; lists replace.
JsonObject deepMerge(Map<String, Object?> base, Map<String, Object?> overlay) {
  final JsonObject result = deepClone(base)! as JsonObject;
  final Map<String, String> existingKeys = <String, String>{
    for (final String key in result.keys) canonicalConfigKey(key): key,
  };

  for (final MapEntry<String, Object?> entry in overlay.entries) {
    final String canonical = canonicalConfigKey(entry.key);
    final String targetKey = existingKeys[canonical] ?? entry.key;
    final Object? current = result[targetKey];
    final Object? incoming = entry.value;

    if (current is Map<String, Object?> && incoming is Map<String, Object?>) {
      result[targetKey] = deepMerge(current, incoming);
    } else {
      result[targetKey] = deepClone(incoming);
    }
    existingKeys[canonical] = targetKey;
  }

  return result;
}

/// Merges [layers] lowest precedence first.
JsonObject deepMergeAll(Iterable<Map<String, Object?>> layers) =>
    layers.fold<JsonObject>(<String, Object?>{}, deepMerge);

/// Drops `-` and `_` and lowercases.
String canonicalConfigKey(String key) =>
    key.replaceAll(_separators, '').toLowerCase();

bool configKeysMatch(String left, String right) =>
    canonicalConfigKey(left) == canonicalConfigKey(right);

final RegExp _separators = RegExp('[-_]');
