# Diene Problems patterns

## Registry with generics and a domain problem

```ts
import { type ErrorPortalConfig, GenericProblemCatalog } from '@atomicloud/diene.problems';
import { z } from 'zod';

const portal: ErrorPortalConfig = {
  scheme: 'https',
  host: config.errorPortal.host,
  landscape: config.landscape,
  platform: config.platform,
  service: config.service,
  module: 'api',
};

export const registry = new GenericProblemCatalog().createGenericProblemRegistry(portal);
export const NoteLocked = registry.register({
  id: 'note_locked',
  title: 'Note Locked',
  status: 423,
  recoverable: true,
  version: 'v1',
  dataSchema: z.object({ noteId: z.string() }).strict(),
});
```

## Minting a Problem

```ts
import { ProblemFactory } from '@atomicloud/diene.problems';

const problems = new ProblemFactory();
const notFound = problems.createProblem(registry.require('entity_not_found'), {
  detail: `Note ${id} does not exist`,
  instance: `/notes/${id}`,
  data: { entityType: 'Note', id },
});
```

## Mapping unknown and HTTP errors

```ts
import { ProblemTransformer } from '@atomicloud/diene.problems';

const transformer = new ProblemTransformer({
  fallback: Unexpected,
  fallbackData: () => ({}),
});
const fromThrown = transformer.fromError(error);
const fromResponse = await transformer.fromHttpError(response);
```

## Emitting the catalog row

```ts
import { ProblemCatalog, ProblemResourceEmitter } from '@atomicloud/diene.problems';

const catalog = new ProblemCatalog(registry);
catalog.declare(registry.require('conflict'), { endpoints: [{ method: 'POST', path: '/notes' }] });
catalog.declare(NoteLocked, { endpoints: [{ method: 'PUT', path: '/notes/{id}' }] });

const resource = new ProblemResourceEmitter().emitProblemResource(catalog, {
  platform: portal.platform,
  service: portal.service,
  module: portal.module,
  landscape: portal.landscape,
  version: 'v1',
});
```

## Asserting a Problem in a test

```ts
import { ProblemTestHelper } from '@atomicloud/diene.problems/test-helper';

const helper = new ProblemTestHelper();

// Arrange
const expected = registry.require('entity_not_found');

// Act
const actual = await service.get('42');

// Assert
helper.expectProblem(actual).toBe(expected, { data: { entityType: 'Note', id: '42' } });
```

Build fixtures with `helper.buildProblem(entry, init)` or
`helper.buildProblemFromRegistry(registry, 'conflict', init)`.
