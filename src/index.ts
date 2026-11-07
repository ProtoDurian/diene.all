// ─── DOMAIN WIRING · the illustrative sample (delete through END to replace the sample) ──────────
import { PinoLogger } from './adapters/pino-logger';
import { RedisKeyValueStore } from './adapters/redis-kv-store';
import { Cleanup } from './lib/sample/cleanup';
import { RedisConfigParser } from './lib/sample/config';
import { KeyComposer } from './lib/sample/key';
import { SampleService } from './lib/sample/service';

const KEY = 'sample key';

if (import.meta.main) {
  const logger = new PinoLogger();
  const keys = new KeyComposer('Bun Base');
  const config = new RedisConfigParser(process.env).parse();

  if (!config.ok) {
    logger.error({ issues: config.issues }, 'invalid redis configuration');
    process.exitCode = 1;
  } else if (config.connection === undefined) {
    logger.info({ key: keys.compose(KEY) }, 'composed key');
  } else {
    const store = new RedisKeyValueStore(config.connection, logger);
    const service = new SampleService(store, keys);
    const value = await new Cleanup(logger).run(
      () => service.roundTrip(KEY, 'sample value'),
      () => store.close(),
    );
    logger.info({ value }, 'round-tripped value');
  }
}
// ─── END DOMAIN WIRING ────────────────────────────────────────────────────────────────────────────
