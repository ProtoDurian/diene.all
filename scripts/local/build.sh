#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

name="$(jq -r .name package.json)"

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

echo "📝 Emitting flat type declarations for the root and /build-time..."
bunx dts-bundle-generator --config dts.config.cjs
cp dist/index.d.ts dist/index.d.cts
cp dist/build-time.d.ts dist/build-time.d.cts

echo "📝 Emitting /test-helper declarations that import the root package..."
bunx tsc -p tsconfig.declarations.json
# The barrel only re-exports helper.ts, so helper.d.ts is the whole /test-helper surface.
[[ "$(cat dist/.declarations/test-helper/index.d.ts)" == "export * from './helper.js';" ]] || {
  echo "❌ src/test-helper/index.ts must be exactly: export * from './helper.js';" >&2
  exit 1
}
cp dist/.declarations/test-helper/helper.d.ts dist/test-helper.d.ts
cp dist/.declarations/test-helper/helper.d.ts dist/test-helper.d.cts
rm -rf dist/.declarations

echo "🔎 Verifying artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/build-time.js dist/build-time.cjs dist/build-time.d.ts dist/build-time.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🔎 Verifying /test-helper imports the root package instead of inlining it..."
for artifact in dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts; do
  grep -qF "'${name}'" "${artifact}" || grep -qF "\"${name}\"" "${artifact}" || {
    echo "❌ ${artifact} must import ${name} by name" >&2
    exit 1
  }
done
for artifact in dist/index.js dist/index.cjs dist/build-time.js dist/build-time.cjs; do
  if grep -qF "${name}" "${artifact}"; then
    echo "❌ ${artifact} must not import ${name}" >&2
    exit 1
  fi
done
roots='ConfigLoader|ConfigRegistry|ConfigValidationError|ConfigValidator|DeepMerger|EnvOverrides|FrozenConfig|LandscapeResolver|Config|ConfigRecord|ConfigSource|EnvRecord|SchemaRegistry|BlockShape'
if grep -nE "^\s*((export )?(declare )?(class|interface|type) (${roots})\b|var (${roots}) = class\b)" \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts; then
  echo "❌ the /test-helper bundle re-declares a root class or type" >&2
  exit 1
fi

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import { ConfigLoader, ConfigRegistry, DeepMerger } from './dist/index.js'; import { BuildTimeValueMapper } from './dist/build-time.js'; import { ConfigStubBuilder, InMemoryConfigSource } from './dist/test-helper.js'; import { z } from 'zod'; const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() })); const loaded = await new ConfigLoader(new InMemoryConfigSource({ base: { server: { port: 1 } }, runtimeEnv: { ATOMI_SERVER__PORT: '2' } }), registry, { prefix: 'ATOMI_' }).load(); const stub = await new ConfigStubBuilder(registry, { prefix: 'ATOMI_' }).build({ base: { server: { port: 3 } } }); if (loaded.get('server').port !== 2 || stub.get('server').port !== 3 || JSON.stringify(new DeepMerger().merge({ a: 1 }, { b: 2 })) !== '{\"a\":1,\"b\":2}' || Object.keys(new BuildTimeValueMapper().map({ ATOMI_CLIENT__X: '1', ATOMI_CLIENT__FARO__BUILD__KEY: 's', ATOMI_SERVER__Y: '2' }, 'ATOMI_')).join() !== 'ATOMI_CLIENT__X') process.exit(1)"
node -e "const { ConfigLoader, ConfigRegistry, DeepMerger } = require('./dist/index.cjs'); const { BuildTimeValueMapper } = require('./dist/build-time.cjs'); const { ConfigStubBuilder, InMemoryConfigSource } = require('./dist/test-helper.cjs'); const { z } = require('zod'); const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() })); if (JSON.stringify(new DeepMerger().merge({ a: 1 }, { b: 2 })) !== '{\"a\":1,\"b\":2}' || Object.keys(new BuildTimeValueMapper().map({ ATOMI_CLIENT__X: '1', ATOMI_CLIENT__FARO__BUILD__KEY: 's', ATOMI_SERVER__Y: '2' }, 'ATOMI_')).join() !== 'ATOMI_CLIENT__X') process.exit(1); Promise.all([new ConfigLoader(new InMemoryConfigSource({ base: { server: { port: 1 } }, runtimeEnv: { ATOMI_SERVER__PORT: '2' } }), registry, { prefix: 'ATOMI_' }).load(), new ConfigStubBuilder(registry, { prefix: 'ATOMI_' }).build({ base: { server: { port: 3 } } })]).then(([loaded, stub]) => { if (loaded.get('server').port !== 2 || stub.get('server').port !== 3) process.exit(1) }).catch(() => process.exit(1))"

echo "🏃 Verifying expectInvalid's error is the root ConfigValidationError (ESM, CJS, mixed)..."
invalid="const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() })); const error = await new ConfigAssertions(new ConfigStubBuilder(registry, { prefix: 'ATOMI_' })).expectInvalid({ base: {} }); if (!(error instanceof ConfigValidationError)) process.exit(1);"
node --input-type=module -e "import { ConfigRegistry, ConfigValidationError } from './dist/index.js'; import { ConfigAssertions, ConfigStubBuilder } from './dist/test-helper.js'; import { z } from 'zod'; ${invalid}"
node -e "const { ConfigRegistry, ConfigValidationError } = require('./dist/index.cjs'); const { ConfigAssertions, ConfigStubBuilder } = require('./dist/test-helper.cjs'); const { z } = require('zod'); (async () => { ${invalid} })().catch(() => process.exit(1))"
node --input-type=module -e "import { createRequire } from 'node:module'; import { ConfigRegistry, ConfigValidationError } from './dist/index.js'; import { z } from 'zod'; const { ConfigAssertions, ConfigStubBuilder } = createRequire(import.meta.url)('./dist/test-helper.cjs'); ${invalid}"
node -e "const { ConfigRegistry, ConfigValidationError } = require('./dist/index.cjs'); const { z } = require('zod'); import('./dist/test-helper.js').then(async ({ ConfigAssertions, ConfigStubBuilder }) => { ${invalid} }).catch(() => process.exit(1))"

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts}, dist/build-time.{js,cjs,d.ts,d.cts}, dist/test-helper.{js,cjs,d.ts,d.cts}"
