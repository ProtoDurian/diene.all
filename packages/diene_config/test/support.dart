import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

final class AppSettings {
  const AppSettings({
    required this.name,
    required this.retries,
    required this.tags,
  });

  final String name;
  final int retries;
  final List<String> tags;

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.name == name &&
      other.retries == retries &&
      other.tags.length == tags.length &&
      _sameTags(other.tags);

  bool _sameTags(List<String> otherTags) {
    for (int index = 0; index < tags.length; index++) {
      if (tags[index] != otherTags[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, retries, Object.hashAll(tags));

  @override
  String toString() => 'AppSettings($name, $retries, $tags)';
}

final ConfigBlock<AppSettings> appBlock = ConfigBlock<AppSettings>(
  key: 'app',
  decode: (Map<String, Object?> values) {
    final Object? name = values['name'];
    final Object? retries = values['retries'];
    if (name is! String || name.isEmpty) {
      throw FormatException('name must be a non-empty string, got $name');
    }
    if (retries is! int || retries < 0) {
      throw FormatException('retries must be a non-negative int, got $retries');
    }
    return AppSettings(
      name: name,
      retries: retries,
      tags: (values['tags'] as List<Object?>? ?? const <Object?>[])
          .map((Object? tag) => '$tag')
          .toList(growable: false),
    );
  },
);

ConfigSchema appSchema({bool rejectUnknownBlocks = true}) => ConfigSchema(
  blocks: <ConfigBlockSchema>[appBlock],
  rejectUnknownBlocks: rejectUnknownBlocks,
);

String describe(Result<Object?> result) => result.match(
  ok: (Object? value) => 'Ok($value)',
  err: (Problem problem) =>
      'Err(${problem.status} ${problem.title}; data=${problem.data})',
);

Matcher get isOk => predicate<Result<Object?>>(
  (Result<Object?> result) => result.isOk,
  'an Ok result',
);

Matcher get isErr => predicate<Result<Object?>>(
  (Result<Object?> result) => result.isErr,
  'an Err result',
);

List<String> errorsOf(Problem problem) =>
    (problem.data['errors']! as List<Object?>)
        .map((Object? error) => '$error')
        .toList(growable: false);
