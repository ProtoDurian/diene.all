#!/usr/bin/env bash
set -euo pipefail

# The node-owned consumer fixture: a throwaway package that `bun add`s the
# library, then proves `import`, `require()` and the TypeScript types of both
# conditions resolve. With no argument it consumes this tree's packed tarball;
# pass a registry spec (e.g. @atomicloud/diene.otel@2.0.0) to consume a real
# publish instead.

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

spec="${1:-}"
if [[ -z ${spec} ]]; then
  [[ ! -f pkg.tgz ]] && echo "❌ pkg.tgz is missing; pack the library first" >&2 && exit 1
  spec="${root_dir}/pkg.tgz"
fi
name="$(jq -r .name package.json)"
tsc="${root_dir}/node_modules/.bin/tsc"
[[ ! -x ${tsc} ]] && echo "❌ ${tsc} is missing; install dependencies first" >&2 && exit 1

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

cat >"${work}/package.json" <<JSON
{ "name": "bun-otel-consumer-fixture", "private": true, "version": "0.0.0" }
JSON
# The public types reference pino's, which need Node's: give the fixture the repo's pinned @types/node.
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
import { OtelBootstrap, TraceError, defaultOtelBlock, otelBlockSchema } from '${name}';
import { AppIdentityBuilder, OtelAssertions, OtelBlockFixtures, OtelTestHarness } from '${name}/test-helper';
const runtime = new OtelBootstrap().init(otelBlockSchema.parse(defaultOtelBlock), new AppIdentityBuilder().build(), { environment: {} });
if (runtime.active.metrics || runtime.active.traces) throw new Error('ESM init exported with every exporter off');
await runtime.shutdown();
const run = new OtelTestHarness().start(new OtelBlockFixtures().otlp());
await run.runtime.traceEmitter.emit({ name: 'esm' }).unwrap();
new OtelAssertions().traceRecords(run.traces, [{ name: 'esm' }]);
const cjsHelper = createRequire(import.meta.url)('${name}/test-helper');
const error = await new cjsHelper.InMemoryTraceEmitter().emit({ name: '' }).unwrapErr();
if (!(error instanceof TraceError)) throw new Error('CJS /test-helper error is not the ESM root TraceError');
JS
cat >"${work}/cjs.cjs" <<JS
const { OtelBootstrap, defaultOtelBlock } = require('${name}');
const { AppIdentityBuilder, OtelAssertions, OtelTestHarness } = require('${name}/test-helper');
const runtime = new OtelBootstrap().init(defaultOtelBlock, new AppIdentityBuilder().build(), { environment: {} });
const run = new OtelTestHarness().start();
run.runtime.traceEmitter
  .emit({ name: 'cjs' })
  .unwrap()
  .then(() => new OtelAssertions().traceRecords(run.traces, [{ name: 'cjs' }]))
  .then(() => runtime.shutdown())
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
JS
for ext in mts cts; do
  cat >"${work}/types.${ext}" <<TS
import { type OtelBlock, OtelBootstrap, type OtelRuntime, type TraceEmitter, otelBlockSchema } from '${name}';
import { AppIdentityBuilder, InMemoryTraceEmitter, OtelBlockFixtures, type OtelHarnessRun, OtelTestHarness } from '${name}/test-helper';
const block: OtelBlock = otelBlockSchema.parse(new OtelBlockFixtures().canonical());
const runtime: OtelRuntime = new OtelBootstrap().init(block, new AppIdentityBuilder().build());
const seam: TraceEmitter = new InMemoryTraceEmitter();
const run: OtelHarnessRun = new OtelTestHarness().start(block);
const live: TraceEmitter = run.traces;
export { live, runtime, seam };
TS
done

echo "📥 bun add ${spec}..."
(cd "${work}" && bun add --no-progress "${spec}")

echo "🔎 import, require() and types..."
(cd "${work}" && node esm.mjs && node cjs.cjs && "${tsc}" -p tsconfig.json)

echo "✅ consumer fixture: ${spec} installs; import, require() and both type conditions resolve for the root and /test-helper"
