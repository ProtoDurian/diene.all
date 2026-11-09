import 'problem_type_uri.dart';

/// The JSON Schema published for a problem that carries no `data`.
const Map<String, Object?> noProblemDataSchema = <String, Object?>{
  'not': <String, Object?>{},
};

/// A versioned problem declaration; a new [version] is a new problem type.
final class ProblemType {
  const ProblemType({
    required this.id,
    required this.title,
    required this.version,
    this.status,
    this.recoverable = false,
    this.dataSchema,
  });

  /// The snake_case wire id.
  final String id;
  final String title;

  /// The contract version segment, e.g. `v1`.
  final String version;

  /// Default HTTP status; catalog export falls back to 500.
  final int? status;

  /// Whether the client may offer a retry.
  final bool recoverable;

  /// JSON Schema of the `data` payload; `null` means no data.
  final Map<String, Object?>? dataSchema;
}

/// Thrown when registering an id twice.
class DuplicateProblemTypeError extends StateError {
  DuplicateProblemTypeError(String id)
    : super('problem type already registered: $id');
}

/// Thrown by [ProblemRegistry.require] for an unknown id.
class UnknownProblemTypeError extends StateError {
  UnknownProblemTypeError(String id)
    : super('no problem type registered for id: $id');
}

/// The problem types of one service, keyed by id.
final class ProblemRegistry {
  ProblemRegistry(this.portal, [Iterable<ProblemType>? types])
    : _types = <String, ProblemType>{} {
    types?.forEach(register);
  }

  final ErrorPortal portal;
  final Map<String, ProblemType> _types;

  void register(ProblemType type) {
    if (_types.containsKey(type.id)) {
      throw DuplicateProblemTypeError(type.id);
    }
    _types[type.id] = type;
  }

  ProblemType? lookup(String id) => _types[id];

  /// Like [lookup], but throws [UnknownProblemTypeError] when absent.
  ProblemType require(String id) =>
      _types[id] ?? (throw UnknownProblemTypeError(id));

  /// Registered types in insertion order.
  Iterable<ProblemType> get entries => _types.values;

  String typeUriFor(ProblemType type) =>
      problemTypeUri(portal: portal, version: type.version, id: type.id);
}

const Map<String, Object?> _string = <String, Object?>{'type': 'string'};

const Map<String, Object?> _entityReferenceSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{'entityType': _string, 'id': _string},
  'required': <String>['entityType', 'id'],
  'additionalProperties': false,
};

/// The generic baseline every service inherits.
abstract final class GenericProblems {
  static const ProblemType validationError = ProblemType(
    id: 'validation_error',
    title: 'Validation error',
    version: 'v1',
    status: 400,
    recoverable: true,
    dataSchema: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'issues': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'path': <String, Object?>{'type': 'array', 'items': _string},
              'message': _string,
              'code': _string,
            },
            'required': <String>['path', 'message'],
            'additionalProperties': false,
          },
        },
      },
      'required': <String>['issues'],
      'additionalProperties': false,
    },
  );

  static const ProblemType entityNotFound = ProblemType(
    id: 'entity_not_found',
    title: 'Entity not found',
    version: 'v1',
    status: 404,
    dataSchema: _entityReferenceSchema,
  );

  static const ProblemType conflict = ProblemType(
    id: 'conflict',
    title: 'Conflict',
    version: 'v1',
    status: 409,
    recoverable: true,
    dataSchema: _entityReferenceSchema,
  );

  static const ProblemType unauthenticated = ProblemType(
    id: 'unauthenticated',
    title: 'Unauthenticated',
    version: 'v1',
    status: 401,
    recoverable: true,
  );

  static const ProblemType unauthorized = ProblemType(
    id: 'unauthorized',
    title: 'Unauthorized',
    version: 'v1',
    status: 403,
  );

  static const ProblemType invalidJson = ProblemType(
    id: 'invalid_json',
    title: 'Invalid JSON',
    version: 'v1',
    status: 400,
    recoverable: true,
  );

  static const List<ProblemType> all = <ProblemType>[
    validationError,
    entityNotFound,
    conflict,
    unauthenticated,
    unauthorized,
    invalidJson,
  ];

  static void registerAll(ProblemRegistry registry) =>
      all.forEach(registry.register);
}
