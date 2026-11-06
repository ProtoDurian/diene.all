import {
  type ErrorPortalConfig,
  GenericProblemCatalog,
  type Problem,
  ProblemCatalog,
  ProblemManifestEmitter,
  type ProblemResource,
  ProblemResourceEmitter,
  ProblemTypeUriBuilder,
} from '@atomicloud/diene.problems';
import { type ProblemExpectation, ProblemTestHelper } from '@atomicloud/diene.problems/test-helper';

const portal: ErrorPortalConfig = {
  scheme: 'https',
  host: 'errors.example',
  landscape: 'pichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
};
const registry = new GenericProblemCatalog().createGenericProblemRegistry(portal);
const uri: string = new ProblemTypeUriBuilder().buildProblemTypeUri(portal, 'v1', 'entity_not_found');
const catalog = new ProblemCatalog(registry);
catalog.declare(registry.require('conflict'), { endpoints: [{ method: 'POST', path: '/notes' }] });
const resource: ProblemResource = new ProblemResourceEmitter().emitProblemResource(catalog, {
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
  landscape: 'pichu',
  version: 'v1',
});
const helper = new ProblemTestHelper();
const problem: Problem = helper.buildProblemFromRegistry(registry, 'unauthorized', {});
const expectation: ProblemExpectation = helper.expectProblem(problem);
expectation.toBe(registry.require('unauthorized'));

void [uri, resource, new ProblemManifestEmitter().emitProblemManifest(registry)];
