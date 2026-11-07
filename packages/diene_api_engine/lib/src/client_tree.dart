import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';

import 'bridge.dart' show BridgeProblems;
import 'config.dart';

/// The backend registry, keyed by LPSM coordinate.
class ClientTree {
  ClientTree();

  final Map<String, BackendConfig> _byKey = <String, BackendConfig>{};

  /// Registers [backend]; a duplicate coordinate is an [Err], not a throw.
  Result<void> register(BackendConfig backend) {
    final String key = backend.coordinate.key;
    if (_byKey.containsKey(key)) {
      return Err<void>(
        Problem(
          type: BridgeProblems.duplicateBackend,
          title: 'Duplicate backend registration',
          status: 409,
          detail: key,
          data: <String, Object?>{'coordinate': backend.coordinate.toMap()},
        ),
      );
    }
    _byKey[key] = backend;
    return const Ok<void>(null);
  }

  BackendConfig? resolve(LpsmCoordinate coordinate) => _byKey[coordinate.key];

  Iterable<BackendConfig> get backends => _byKey.values;

  bool contains(LpsmCoordinate coordinate) =>
      _byKey.containsKey(coordinate.key);
}
