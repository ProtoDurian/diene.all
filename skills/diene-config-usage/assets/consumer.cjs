const { ConfigLoader, ConfigRegistry, YamlConfigSource } = require('@atomicloud/diene.config');
const { z } = require('zod');

const registry = ConfigRegistry.create().register('server', z.object({ port: z.number(), host: z.string() }));

new ConfigLoader(new YamlConfigSource({ dir: 'config', env: process.env }), registry, { prefix: 'ATOMI_' })
  .load()
  .then(config => console.log(config.get('server').host))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
