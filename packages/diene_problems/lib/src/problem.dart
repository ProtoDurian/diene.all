import 'dart:convert';

/// An RFC 9457 problem-details envelope with the `data` and `recoverable`
/// extensions.
final class Problem {
  /// Creates a problem envelope; [type] must come from `problemTypeUri`.
  const Problem({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.recoverable = false,
    this.data,
  });

  /// Parses an envelope; a missing or non-object `data` reads as no data.
  factory Problem.fromJson(Map<String, Object?> json) {
    final Object? rawData = json['data'];
    return Problem(
      type: json['type'] as String? ?? 'about:blank',
      title: json['title'] as String? ?? 'Unexpected problem',
      status: (json['status'] as num?)?.toInt() ?? 500,
      detail: json['detail'] as String?,
      instance: json['instance'] as String?,
      recoverable: json['recoverable'] as bool? ?? false,
      data: rawData is Map<Object?, Object?>
          ? rawData.map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            )
          : null,
    );
  }

  final String type;
  final String title;
  final int status;
  final String? detail;
  final String? instance;

  /// Whether the client may offer a retry.
  final bool recoverable;

  /// The typed payload; `null` means the problem carries no data.
  final Map<String, Object?>? data;

  /// The wire form; `data` is omitted, never `null`, when absent.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'title': title,
    'status': status,
    if (detail != null) 'detail': detail,
    if (instance != null) 'instance': instance,
    'recoverable': recoverable,
    if (data != null) 'data': data,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Problem && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'Problem($type, $status, $title)';
}

/// The id of the fallback problem for a value no registry recognises.
const String uncataloguedProblemId = 'uncatalogued';
