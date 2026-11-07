# Faking config in tests

Import `@atomicloud/diene.config/test-helper`; never mutate `process.env` or
write real files in a unit test.

```ts
import { ConfigRegistry } from '@atomicloud/diene.config';
import { ConfigAssertions, ConfigStubBuilder, LandscapeConfigSource } from '@atomicloud/diene.config/test-helper';
import { z } from 'zod';

const registry = ConfigRegistry.create().register('server', z.object({ port: z.number(), host: z.string() }));
const builder = new ConfigStubBuilder(registry, { prefix: 'ATOMI_' });

// A validated config from plain-object tiers; it always passes the registry.
const config = await builder.build({ base: { server: { port: 80, host: 'h' } } });

// Assert a tier set fails final-layer validation.
const assertions = new ConfigAssertions(builder);
const error = await assertions.expectInvalid({ base: { server: { port: 'x', host: 'h' } } });

// A source whose base carries `app.landscape`, so the loader picks that overlay.
const source = new LandscapeConfigSource('prod', {
  base: { server: { port: 80, host: 'h' } },
  overlays: { prod: { server: { host: 'prod' } } },
});
```

## Real-vs-fake contract parity

Run ONE behavioural suite against both `YamlConfigSource` (real files + env) and
`InMemoryConfigSource` (plain objects) and assert identical `config.all()`. The
fakes feed the same `ConfigLoader` as production.
