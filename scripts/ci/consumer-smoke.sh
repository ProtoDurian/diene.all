#!/usr/bin/env bash
set -euo pipefail

# The node-owned consumer fixture: a throwaway package that `bun add`s the
# library, then proves `import`, `require()` and the TypeScript types of both
# conditions resolve for all three entry points. With no argument it consumes
# this tree's packed tarball; pass a registry spec (e.g.
# @atomicloud/diene.config@2.0.0) to consume a real publish instead.

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

spec="${1:-}"
if [[ -z ${spec} ]]; then
  [[ ! -f pkg.tgz ]] && echo "❌ pkg.tgz is missing; pack the library first" >&2 && exit 1
  spec="${root_dir}/pkg.tgz"
fi
name="$(jq -r .name package.json)"
zod="zod@$(jq -r .dependencies.zod package.json)"
tsc="${root_dir}/node_modules/.bin/tsc"
[[ ! -x ${tsc} ]] && echo "❌ ${tsc} is missing; install dependencies first" >&2 && exit 1

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

cat >"${work}/package.json" <<JSON
{ "name": "bun-config-consumer-fixture", "private": true, "version": "0.0.0" }
JSON
# The public types reference node:fs: give the fixture the repo's pinned @types/node.
cat >"${work}/tsconfig.json" <<JSON
{
  "compilerOptions": {
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "strict": true,
    "noEmit": true,
    "types": ["node"],
    "typeRoots": ["${root_dir}/node_modules/@types"]
  },
  "include": ["*.mts", "*.cts"]
}
JSON
cat >"${work}/esm.mjs" <<JS
import { createRequire } from 'node:module';
import { ConfigLoader, ConfigRegistry, ConfigValidationError } from '${name}';
import { BuildTimeValueMapper } from '${name}/build-time';
import { ConfigAssertions, ConfigStubBuilder, InMemoryConfigSource } from '${name}/test-helper';
import { z } from 'zod';
const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
const source = new InMemoryConfigSource({ base: { server: { port: 1 } }, runtimeEnv: { ATOMI_SERVER__PORT: '2' } });
const config = await new ConfigLoader(source, registry, { prefix: 'ATOMI_' }).load();
if (config.get('server').port !== 2) throw new Error('ESM loader returned the wrong port');
if (new BuildTimeValueMapper().map({ ATOMI_X: '1', Y: '2' }, 'ATOMI_').ATOMI_X !== '1') throw new Error('ESM build-time map is wrong');
const error = await new ConfigAssertions(new ConfigStubBuilder(registry)).expectInvalid({ base: {} });
if (error.issues.length === 0) throw new Error('ESM asserter missed an invalid config');
if (!(error instanceof ConfigValidationError)) throw new Error('ESM /test-helper error is not the root ConfigValidationError');
const cjsHelper = createRequire(import.meta.url)('${name}/test-helper');
const mixed = await new cjsHelper.ConfigAssertions(new cjsHelper.ConfigStubBuilder(registry)).expectInvalid({ base: {} });
if (!(mixed instanceof ConfigValidationError)) throw new Error('CJS /test-helper error is not the ESM root ConfigValidationError');
JS
cat >"${work}/cjs.cjs" <<JS
const { ConfigLoader, ConfigRegistry, ConfigValidationError } = require('${name}');
const { BuildTimeValueMapper } = require('${name}/build-time');
const { ConfigAssertions, ConfigStubBuilder, InMemoryConfigSource } = require('${name}/test-helper');
const { z } = require('zod');
const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
const source = new InMemoryConfigSource({ base: { server: { port: 1 } }, runtimeEnv: { ATOMI_SERVER__PORT: '2' } });
if (new BuildTimeValueMapper().map({ ATOMI_X: '1', Y: '2' }, 'ATOMI_').ATOMI_X !== '1') throw new Error('CJS build-time map is wrong');
Promise.all([
  new ConfigLoader(source, registry, { prefix: 'ATOMI_' }).load(),
  new ConfigAssertions(new ConfigStubBuilder(registry)).expectInvalid({ base: {} }),
]).then(([config, error]) => {
  if (config.get('server').port !== 2) throw new Error('CJS loader returned the wrong port');
  if (error.issues.length === 0) throw new Error('CJS asserter missed an invalid config');
  if (!(error instanceof ConfigValidationError)) throw new Error('CJS /test-helper error is not the root ConfigValidationError');
}).catch(error => {
  console.error(error);
  process.exit(1);
});
JS
for ext in mts cts; do
  # A root-entry Config and registry must interoperate with the /test-helper ones.
  cat >"${work}/types.${ext}" <<TS
import { type Config, ConfigLoader, ConfigRegistry } from '${name}';
import { BuildTimeValueMapper } from '${name}/build-time';
import { ConfigStubBuilder, InMemoryConfigSource } from '${name}/test-helper';
import { z } from 'zod';
const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));
const read = (config: Config<{ server: z.ZodObject<{ port: z.ZodNumber }> }>): number => config.get('server').port;
const stub: Promise<number> = new ConfigStubBuilder(registry).build({}).then(read);
const live: Promise<number> = new ConfigLoader(new InMemoryConfigSource(), registry, { prefix: 'ATOMI_' }).load().then(read);
const map: Record<string, string> = new BuildTimeValueMapper().map({}, 'ATOMI_');
export { live, map, stub };
TS
done

echo "📥 bun add ${spec} ${zod}..."
(cd "${work}" && bun add --no-progress "${spec}" "${zod}")

echo "🔎 import, require() and types..."
(cd "${work}" && node esm.mjs && node cjs.cjs && "${tsc}" -p tsconfig.json)

echo "✅ consumer fixture: ${spec} installs; import, require() and both type conditions resolve for all three entry points"
