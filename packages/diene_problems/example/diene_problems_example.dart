import 'package:diene_problems/diene_problems.dart';

Future<void> main() async {
  const ErrorPortal portal = ErrorPortal(
    scheme: 'https',
    host: 'errors.atomi.cloud',
    landscape: 'raichu',
    platform: 'nitroso',
    service: 'zinc',
    module: 'api',
  );

  final ProblemRegistry registry = ProblemRegistry(portal);
  GenericProblems.registerAll(registry);
  final ProblemType notFound = registry.require('entity_not_found');

  final Problem problem = Problem(
    type: registry.typeUriFor(notFound),
    title: notFound.title,
    status: notFound.status ?? 500,
    detail: 'Note 42 does not exist',
    instance: '/notes/42',
    recoverable: notFound.recoverable,
    data: const <String, Object?>{'entityType': 'note', 'id': '42'},
  );
  assert(Problem.fromJson(problem.toJson()) == problem, 'round-trips');

  final Problem folded = fromObject(<String, Object?>{
    'problemId': 'validation_error',
    'data': <String, Object?>{'issues': <Object?>[]},
  }, options: TransformOptions(portal: portal, registry: registry));
  assert(folded.status == 400, 'the registry supplies the status');

  final Problem local = await const LocalError(
    NoopErrorSink(),
    portal: portal,
  ).wrap(StateError('render failed'), StackTrace.current);
  assert(local.data!.containsKey('stackTrace'), 'carries the stack trace');

  final ProblemCatalog catalog = ProblemCatalog(portal: portal)
    ..addGenerics()
    ..addType(
      notFound,
      endpoints: const <CatalogEndpoint>[
        CatalogEndpoint(method: 'GET', path: '/notes/{id}'),
      ],
    );
  final Map<String, Object?> resource = catalog.toProblemResource(
    version: 'v1',
  );
  assert(
    (resource['metadata']! as Map<String, Object?>)['name'] ==
        'zinc.api.raichu.v1',
    'one Problem CR per row',
  );
}
