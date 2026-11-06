#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

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

echo "📝 Emitting bundled declarations..."
bunx dts-bundle-generator -o dist/index.d.ts src/index.ts --no-check
cp dist/index.d.ts dist/index.d.cts
bunx tsc -p tsconfig.declarations.json
# The helper names the root package, so one declaration serves both conditions.
cp dist/.declarations/test-helper/index.d.ts dist/test-helper.d.ts
cp dist/.declarations/test-helper/index.d.ts dist/test-helper.d.cts
rm -rf dist/.declarations

echo "🔎 Verifying build artifacts..."
for artifact in \
  dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts \
  dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts dist/test-helper.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ Build artifact missing: ${artifact}" >&2 && exit 1
done

cmp -s dist/index.d.ts dist/index.d.cts || {
  echo "❌ dist/index.d.cts must be a byte-copy of dist/index.d.ts" >&2
  exit 1
}
cmp -s dist/test-helper.d.ts dist/test-helper.d.cts || {
  echo "❌ dist/test-helper.d.cts must be a byte-copy of dist/test-helper.d.ts" >&2
  exit 1
}

echo "🔎 Verifying the helper externalizes the root package (no registry duplication)..."
for artifact in dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts; do
  grep -qF "@atomicloud/diene.problems" "${artifact}" || {
    echo "❌ ${artifact} must import the root package by name, not inline it" >&2
    exit 1
  }
done
if grep -qF "@atomicloud/diene.problems" dist/index.js; then
  echo "❌ dist/index.js must not self-import the problems package" >&2
  exit 1
fi
if grep -nE '\bclass (ProblemRegistry|ProblemRegistryError|ProblemFactory|ProblemTypeUriBuilder)\b|\binterface (Problem|RegisteredProblem|ProblemInit)\b' dist/test-helper.js dist/test-helper.cjs dist/test-helper.d.ts; then
  echo "❌ the helper bundle re-declares a root type; it must import it from the root package" >&2
  exit 1
fi

echo "🏃 Verifying ESM and CJS runtime exports and shared registry identity..."
uri="https://errors.example/docs/pichu/nitroso/zinc/api/v1/entity_not_found"
portal="{ scheme: 'https', host: 'errors.example', landscape: 'pichu', platform: 'nitroso', service: 'zinc', module: 'api' }"
node --input-type=module -e "import { GenericProblemCatalog } from './dist/index.js'; const r = new GenericProblemCatalog().createGenericProblemRegistry(${portal}); if (r.require('entity_not_found').type !== '${uri}') process.exit(1)"
node -e "const { GenericProblemCatalog } = require('./dist/index.cjs'); const r = new GenericProblemCatalog().createGenericProblemRegistry(${portal}); if (r.require('entity_not_found').type !== '${uri}') process.exit(1)"
node --input-type=module -e "import { GenericProblemCatalog, ProblemRegistryError } from './dist/index.js'; import { ProblemTestHelper } from './dist/test-helper.js'; const r = new GenericProblemCatalog().createGenericProblemRegistry(${portal}); const h = new ProblemTestHelper(); h.expectProblem(h.buildProblemFromRegistry(r, 'conflict', { data: { entityType: 'Note', id: '1' } })).toBe(r.require('conflict')); try { h.buildProblemFromRegistry(r, 'missing', {}); process.exit(1) } catch (e) { if (!(e instanceof ProblemRegistryError)) process.exit(1) }"
node -e "const { GenericProblemCatalog, ProblemRegistryError } = require('./dist/index.cjs'); const { ProblemTestHelper } = require('./dist/test-helper.cjs'); const r = new GenericProblemCatalog().createGenericProblemRegistry(${portal}); const h = new ProblemTestHelper(); h.expectProblem(h.buildProblemFromRegistry(r, 'conflict', { data: { entityType: 'Note', id: '1' } })).toBe(r.require('conflict')); try { h.buildProblemFromRegistry(r, 'missing', {}); process.exit(1) } catch (e) { if (!(e instanceof ProblemRegistryError)) process.exit(1) }"

echo "🔎 Verifying Node16 consumer type resolution..."
bunx tsc -p fixtures/package-consumer/tsconfig.json

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts} and dist/test-helper.{js,cjs,d.ts,d.cts}"
