# Diene Problems patterns

## Rules

- A Problem has `type`, `title`, `status` (400–599), optional `detail` and
  `instance`, and a `data` member only when its entry has a `dataSchema`.
  Without one, `data` is omitted, never `null` or `{}`.
- Type URIs are
  `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`,
  built only by the registry from `ErrorPortalConfig`. `scheme` is `http` or
  `https`, `version` is `v1`, `v2`, …, `id` is snake_case.
- A published `version` never changes meaning; bump it to mint a new type.
- The generics are fixed: `validation_error` 400 recoverable
  `{ issues: [{ path, message, code? }] }`; `entity_not_found` 404 fatal and
  `conflict` 409 recoverable, both `{ entityType, id }`; `unauthenticated` 401
  recoverable, `unauthorized` 403 fatal and `invalid_json` 400 recoverable,
  all three without data. They register at your row's version.
- One `Problem` resource per `(platform, service, module, landscape, version)`
  row. The four identity segments must be DNS-1123 labels (lowercase, digits,
  `-`, at most 63 characters).
- `instance` only comes from your `instance` mapper; the transformer never
  copies an upstream URL into it.

## Registry with generics and a domain problem

```ts
import { type ErrorPortalConfig, GenericProblemCatalog } from '@atomicloud/diene.problems';
import { z } from 'zod';

const portal: ErrorPortalConfig = {
  scheme: 'https',
  host: 'errors.example.com',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
};

const registry = new GenericProblemCatalog().createGenericProblemRegistry(portal, 'v1');
const NoteLocked = registry.register({
  id: 'note_locked',
  title: 'Note Locked',
  status: 423,
  recoverable: true,
  version: 'v1',
  dataSchema: z.object({ noteId: z.string() }).strict(),
});
const Unexpected = registry.register({
  id: 'unexpected_error',
  title: 'Unexpected Error',
  status: 500,
  recoverable: false,
  version: 'v1',
});
```

## Minting a Problem

```ts
import { ProblemFactory } from '@atomicloud/diene.problems';

const problems = new ProblemFactory();
const notFound = problems.createProblem(registry.require('entity_not_found'), {
  detail: 'Note 42 does not exist',
  instance: '/notes/42',
  data: { entityType: 'Note', id: '42' },
});
const locked = problems.createProblem(NoteLocked, { data: { noteId: '42' } });
const denied = problems.createProblem(registry.require('unauthorized'), { detail: 'No access to note 42' });
```

## Mapping unknown and HTTP errors

```ts
import { ProblemTransformer } from '@atomicloud/diene.problems';

const transformer = new ProblemTransformer({
  fallback: Unexpected,
  instance: () => '/notes/42',
});
const fromThrown = transformer.fromError(new Error('database unavailable'));
const fromResponse = await transformer.fromHttpError(await fetch('https://upstream.example.com/notes/42'));
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
import { it } from 'bun:test';
import { ProblemTestHelper } from '@atomicloud/diene.problems/test-helper';

const helper = new ProblemTestHelper();

it('returns entity_not_found for a missing note', async () => {
  // Arrange
  const expected = registry.require('entity_not_found');

  // Act
  const actual = await notes.get('42');

  // Assert
  helper.expectProblem(actual).toBe(expected, { data: { entityType: 'Note', id: '42' } });
});
```

Build fixtures with `helper.buildProblem(entry, init)` or
`helper.buildProblemFromRegistry(registry, 'conflict', init)`.
