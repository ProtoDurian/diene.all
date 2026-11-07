// ignore_for_file: avoid_print
import 'package:diene_api_engine/diene_api_engine.dart';

Future<void> main() async {
  final BackendConfig core = BackendConfig(
    coordinate: const LpsmCoordinate(
      landscape: 'raichu',
      platform: 'lithium',
      service: 'api',
      module: 'core',
    ),
    baseUrl: Uri.parse('https://core.raichu.cluster.atomi.cloud'),
    resourceName: 'core',
  );
  final BackendConfig billing = BackendConfig(
    coordinate: const LpsmCoordinate(
      landscape: 'raichu',
      platform: 'lithium',
      service: 'api',
      module: 'billing',
    ),
    baseUrl: Uri.parse('https://billing.raichu.cluster.atomi.cloud'),
    resourceName: 'billing',
  );

  final ApiEngineConfig config = ApiEngineConfig(
    backends: <BackendConfig>[core, billing],
    rescue: RescueConfig(
      enabled: true,
      issuer: Uri.parse(
        'https://api.lithium.aldehyde.raichu.cluster.atomi.cloud',
      ),
      catalogHosts: const <String>['rescue.cluster.atomi.cloud'],
      endpointSuffixAllowlist: const <String>['.cluster.atomi.cloud'],
    ),
  );

  // Pass `auth:` (an IAuth) to send each backend its own token.
  final ApiEngine engine = ApiEngine.fromConfig(config);
  final Backend? backend = engine.backend(core.coordinate);
  if (backend == null) {
    return;
  }

  final Result<Map<String, Object?>> result = await backend
      .call<Map<String, Object?>>(
        method: HttpMethod.get,
        path: '/users/42',
        decode: (Map<String, Object?> json) => json,
      );

  switch (result) {
    case Ok<Map<String, Object?>>(:final value):
      print('user: $value');
    case Err<Map<String, Object?>>(:final problem):
      print(
        'failed ${problem.status}: ${problem.title} '
        '(recoverable: ${problem.recoverable})',
      );
  }
}
