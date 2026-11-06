// Production dead-code root: references every public export.
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_problems/test_helper.dart';

Future<void> main() async {
  final ErrorPortal portal = anErrorPortal();
  final ProblemRegistry registry = ProblemRegistry(portal, <ProblemType>[
    GenericProblems.validationError,
  ]);
  GenericProblems.registerAll(ProblemRegistry(portal));
  final ProblemType type = registry.require('validation_error');
  final List<Object?> used = <Object?>[
    registry.lookup('validation_error'),
    registry.entries,
    registry.portal,
    type.title,
    type.dataSchema,
    GenericProblems.entityNotFound,
    GenericProblems.conflict,
    GenericProblems.unauthenticated,
    GenericProblems.unauthorized,
    GenericProblems.invalidJson,
    GenericProblems.all,
    noProblemDataSchema,
    problemSegmentPattern,
    problemWireIdPattern,
    problemVersionPattern,
    portal.scheme,
    portal.host,
    portal.landscape,
    portal.platform,
    portal.service,
    portal.module,
  ];

  final Problem problem = Problem.fromJson(
    aProblem(detail: 'd', instance: '/i').toJson(),
  );
  expectProblem(
    problem,
    type: problem.type,
    title: problem.title,
    status: problem.status,
    recoverable: problem.recoverable,
    detail: problem.detail,
    instance: problem.instance,
    data: problem.data,
  );
  used
    ..add(problem.hashCode)
    ..add(problem.toString());

  final Problem folded = fromObject(
    StateError('x'),
    options: TransformOptions(
      portal: portal,
      registry: registry,
      defaultStatus: 500,
      defaultVersion: 'v1',
    ),
  );
  used.add(folded.type.endsWith(uncataloguedProblemId));

  final LocalError localError = LocalError(const NoopErrorSink());
  final Problem local = await localError.wrap('x', StackTrace.empty);
  used
    ..add(local)
    ..add(localError.sink)
    ..add(localError.portal);

  final CatalogEntry entry = aCatalogEntry(id: 'conflict');
  final ProblemCatalog catalog = ProblemCatalog(
    portal: ErrorPortal.localError,
    entries: <CatalogEntry>[entry],
  )..addGenerics();
  used
    ..add(catalog.lookup('conflict'))
    ..add(catalog.entries)
    ..add(catalog.toCrdContent())
    ..add(catalog.portal)
    ..add(entry.title)
    ..add(entry.status)
    ..add(entry.recoverable)
    ..add(entry.dataSchema)
    ..add(entry.endpoints)
    ..add(const CatalogEndpoint(method: 'GET', path: '/').method);

  try {
    catalog.toProblemResource(version: 'v1');
  } on ProblemResourceError catch (error) {
    used.add(error.message);
  }
  try {
    registry.register(type);
  } on DuplicateProblemTypeError catch (error) {
    used.add(error);
  }
  try {
    registry.require('missing');
  } on UnknownProblemTypeError catch (error) {
    used.add(error);
  }
  try {
    problemTypeUri(portal: portal, version: 'v0', id: 'x');
  } on InvalidProblemTypeSegmentError catch (error) {
    used.add(error.name);
  }
  try {
    expectProblem('not a problem', noData: true);
  } on ProblemMatcherError catch (error) {
    used.add(error.message);
  }
  if (used.isEmpty) {
    throw StateError('unreachable');
  }
}
