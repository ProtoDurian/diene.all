#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

name="$(jq -r .name package.json)"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundles..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.js --format esm --target node --packages external

echo "🔨 Building CommonJS bundles..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --packages external
bun build ./src/test-helper/index.ts --outfile dist/test-helper.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting flat root type declarations..."
bunx dts-bundle-generator -o dist/index.d.ts src/index.ts --no-check
cp dist/index.d.ts dist/index.d.cts

echo "📝 Emitting /test-helper declarations that import the root package..."
bunx tsc -p tsconfig.declarations.json
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
for artifact in dist/index.js dist/index.cjs; do
  if grep -qF "${name}" "${artifact}"; then
    echo "❌ ${artifact} must not import ${name}" >&2
    exit 1
  fi
done
roots='OtelBootstrap|OtelPlanner|ResourceIdentityMapper|TraceError|TraceRecordValidator|OtelSchemaFactory|OtelBlock|OtelRuntime|TraceEmitter|TraceRecord|AppIdentity'
if grep -nE "^\s*((export )?(declare )?(class|interface|type) (${roots})\b|var (${roots}) = class\b)" \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts; then
  echo "❌ the /test-helper bundle re-declares a root class or type" >&2
  exit 1
fi

echo "🏃 Verifying ESM and CJS runtime exports..."
proof="const runtime = new OtelBootstrap().init(defaultOtelBlock, new AppIdentityBuilder().build(), { environment: {} }); const run = new OtelTestHarness().start(); const error = await run.traces.emit({ name: '' }).unwrapErr(); if (runtime.active.traces || otelBlockSchema.parse(defaultOtelBlock).traces.sampler.ratio !== 1 || !(error instanceof TraceError)) process.exit(1); await runtime.shutdown();"
node --input-type=module -e "import { OtelBootstrap, TraceError, defaultOtelBlock, otelBlockSchema } from './dist/index.js'; import { AppIdentityBuilder, OtelTestHarness } from './dist/test-helper.js'; ${proof}"
node -e "const { OtelBootstrap, TraceError, defaultOtelBlock, otelBlockSchema } = require('./dist/index.cjs'); const { AppIdentityBuilder, OtelTestHarness } = require('./dist/test-helper.cjs'); (async () => { ${proof} })().catch(() => process.exit(1))"

echo "🏃 Verifying TraceError, TelemetryLifecycleError and OtelAssertionError cross the ESM and CJS builds, and subclasses stay narrow..."
identity="const cjs = require('./dist/index.cjs'); const cjsHelper = require('./dist/test-helper.cjs'); class Narrow extends TraceError {} class NarrowLifecycle extends TelemetryLifecycleError {} const caught = run => { try { run(); } catch (error) { return error; } }; const fromCjs = caught(() => new cjsHelper.OtelAssertions().payload(1, 2)); const fromEsm = caught(() => new OtelAssertions().payload(1, 2)); if (!(new cjs.TraceError('io', 'emit', 'x') instanceof TraceError) || !(new TraceError('io', 'emit', 'x') instanceof cjs.TraceError) || !(fromCjs instanceof OtelAssertionError) || !(fromEsm instanceof cjsHelper.OtelAssertionError) || new TraceError('io', 'emit', 'x') instanceof Narrow || !(new Narrow('io', 'emit', 'x') instanceof cjs.TraceError) || !(new cjs.TelemetryLifecycleError('logs', 'flush', 'x') instanceof TelemetryLifecycleError) || !(new TelemetryLifecycleError('logs', 'flush', 'x') instanceof cjs.TelemetryLifecycleError) || new TelemetryLifecycleError('logs', 'flush', 'x') instanceof NarrowLifecycle || new cjs.TelemetryLifecycleError('logs', 'flush', 'x') instanceof NarrowLifecycle || !(new NarrowLifecycle('logs', 'flush', 'x') instanceof cjs.TelemetryLifecycleError)) process.exit(1);"
node --input-type=module -e "import { createRequire } from 'node:module'; import { TelemetryLifecycleError, TraceError } from './dist/index.js'; import { OtelAssertionError, OtelAssertions } from './dist/test-helper.js'; const require = createRequire(import.meta.url); ${identity}"

echo "🏃 Verifying an unreadable TLS file fails init with an OtlpTlsFileError both builds recognise..."
tls_identity="const cjs = require('./dist/index.cjs'); class NarrowTls extends OtlpTlsFileError {} const variable = 'OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY'; const environment = { OTEL_LOGS_EXPORTER: 'none', OTEL_METRICS_EXPORTER: 'none', OTEL_TRACES_EXPORTER: 'otlp', [variable]: '/nonexistent/otel/client.key' }; const app = { landscape: 'l', platform: 'p', service: 's', module: 'm', version: '1.0.0' }; const failed = bootstrap => { try { bootstrap.init(defaultOtelBlock, app, { environment }); } catch (error) { return error; } }; const fromCjs = failed(new cjs.OtelBootstrap()); const fromEsm = failed(new OtelBootstrap()); if (!(fromCjs instanceof OtlpTlsFileError) || !(fromEsm instanceof cjs.OtlpTlsFileError) || fromCjs.variable !== variable || fromEsm.variable !== variable || fromCjs instanceof NarrowTls || fromEsm instanceof NarrowTls || new cjs.OtlpTlsFileError(variable, 'p', 'x') instanceof NarrowTls || !(new NarrowTls(variable, 'p', 'x') instanceof cjs.OtlpTlsFileError)) process.exit(1);"
node --input-type=module -e "import { createRequire } from 'node:module'; import { defaultOtelBlock, OtelBootstrap, OtlpTlsFileError } from './dist/index.js'; const require = createRequire(import.meta.url); ${tls_identity}"

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts} and dist/test-helper.{js,cjs,d.ts,d.cts}"
