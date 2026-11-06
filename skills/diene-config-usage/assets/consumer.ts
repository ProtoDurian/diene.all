import { ConfigLoader, ConfigRegistry, YamlConfigSource } from '@atomicloud/diene.config';
import { z } from 'zod';

const ServerBlock = z.object({ port: z.number(), host: z.string(), tags: z.array(z.string()) });

const registry = ConfigRegistry.create().register('server', ServerBlock);

// config/ holds config.yaml (full defaults) and <landscape>.config.yaml overlays.
const source = new YamlConfigSource({ dir: 'config', env: process.env });

const config = await new ConfigLoader(source, registry, {
  prefix: 'ATOMI_',
  landscape: process.env.LANDSCAPE,
}).load();

const server = config.get('server');
console.log(server.host, server.port, server.tags);
