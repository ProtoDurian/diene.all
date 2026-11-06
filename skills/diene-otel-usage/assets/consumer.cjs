const { OtelBootstrap, defaultOtelBlock } = require('@atomicloud/diene.otel');

const app = { landscape: 'lapras', platform: 'atomi', service: 'sample', module: 'api', version: '1.0.0' };
const runtime = new OtelBootstrap().init(defaultOtelBlock, app);

runtime.traceEmitter
  .emit({ name: 'startup', attributes: { port: 8080 } })
  .unwrap()
  .then(() => runtime.shutdown())
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
