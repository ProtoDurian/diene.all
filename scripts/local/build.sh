#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundles..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --packages external
bun build ./src/build-time.ts --outfile dist/build-time.js --format esm --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.js --format esm --target node --packages external

echo "🔨 Building CommonJS bundles..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --packages external
bun build ./src/build-time.ts --outfile dist/build-time.cjs --format cjs --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting flat type declarations (single shared program)..."
bunx dts-bundle-generator --config dts.config.cjs
cp dist/index.d.ts dist/index.d.cts
cp dist/build-time.d.ts dist/build-time.d.cts
cp dist/test-helper.d.ts dist/test-helper.d.cts

echo "🔎 Verifying artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/build-time.js dist/build-time.cjs dist/build-time.d.ts dist/build-time.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import { ConfigLoader, ConfigRegistry, DeepMerger } from './dist/index.js'; import { BuildTimeValueMapper } from './dist/build-time.js'; import { ConfigStubBuilder, InMemoryConfigSource } from './dist/test-helper.js'; import { z } from 'zod'; const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() })); const loaded = await new ConfigLoader(new InMemoryConfigSource({ base: { server: { port: 1 } }, runtimeEnv: { ATOMI_SERVER__PORT: '2' } }), registry, { prefix: 'ATOMI_' }).load(); const stub = await new ConfigStubBuilder(registry).build({ base: { server: { port: 3 } } }); if (loaded.get('server').port !== 2 || stub.get('server').port !== 3 || JSON.stringify(new DeepMerger().merge({ a: 1 }, { b: 2 })) !== '{\"a\":1,\"b\":2}' || new BuildTimeValueMapper().map({ ATOMI_X: '1', Y: '2' }, 'ATOMI_').ATOMI_X !== '1') process.exit(1)"
node -e "const { ConfigLoader, ConfigRegistry, DeepMerger } = require('./dist/index.cjs'); const { BuildTimeValueMapper } = require('./dist/build-time.cjs'); const { ConfigStubBuilder, InMemoryConfigSource } = require('./dist/test-helper.cjs'); const { z } = require('zod'); const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() })); if (JSON.stringify(new DeepMerger().merge({ a: 1 }, { b: 2 })) !== '{\"a\":1,\"b\":2}' || new BuildTimeValueMapper().map({ ATOMI_X: '1', Y: '2' }, 'ATOMI_').ATOMI_X !== '1') process.exit(1); Promise.all([new ConfigLoader(new InMemoryConfigSource({ base: { server: { port: 1 } }, runtimeEnv: { ATOMI_SERVER__PORT: '2' } }), registry, { prefix: 'ATOMI_' }).load(), new ConfigStubBuilder(registry).build({ base: { server: { port: 3 } } })]).then(([loaded, stub]) => { if (loaded.get('server').port !== 2 || stub.get('server').port !== 3) process.exit(1) }).catch(() => process.exit(1))"

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts}, dist/build-time.{js,cjs,d.ts,d.cts}, dist/test-helper.{js,cjs,d.ts,d.cts}"
