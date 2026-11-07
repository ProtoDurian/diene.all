library;

import 'package:diene_result/diene_result.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'util_problem.dart';

enum NamespacedKeyField { namespace, key }

// Combining-mark blocks stripped after NFKD.
final RegExp _combiningMarks = RegExp(
  '[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]',
);
final RegExp _notAsciiAlphaNumeric = RegExp('[^a-z0-9]+');
final RegExp _edgeHyphens = RegExp(r'^-+|-+$');

/// NFKD, drop accents, lowercase, join ASCII alphanumeric runs with `-`.
String slugify(String input) => unicode
    .nfkd(input)
    .replaceAll(_combiningMarks, '')
    .toLowerCase()
    .trim()
    .replaceAll(_notAsciiAlphaNumeric, '-')
    .replaceAll(_edgeHyphens, '');

/// Slugifies both parts into `namespace:key`; an empty part is `invalid_input`.
Result<String> namespacedKey(String namespace, String key) {
  final String normalizedNamespace = slugify(namespace);
  if (normalizedNamespace.isEmpty) {
    return invalidUtilInput<String>(
      util: UtilName.slug,
      operation: 'namespacedKey',
      field: NamespacedKeyField.namespace.name,
      message: 'namespace must not slugify to empty',
    );
  }

  final String normalizedKey = slugify(key);
  if (normalizedKey.isEmpty) {
    return invalidUtilInput<String>(
      util: UtilName.slug,
      operation: 'namespacedKey',
      field: NamespacedKeyField.key.name,
      message: 'key must not slugify to empty',
    );
  }

  return Ok<String>('$normalizedNamespace:$normalizedKey');
}
