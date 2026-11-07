#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

echo "🧹 Cleaning dist/..."
rm -rf dist

echo "🔨 Building ESM bundle..."
bun build ./src/index.ts --outfile dist/index.js --format esm --target node --packages external

echo "🔨 Building CJS bundle..."
bun build ./src/index.ts --outfile dist/index.cjs --format cjs --target node --packages external

echo "🔠 Typechecking..."
bunx tsc -p tsconfig.json

echo "📝 Emitting flat type declarations..."
bunx dts-bundle-generator -o dist/index.d.ts src/index.ts --no-check
cp dist/index.d.ts dist/index.d.cts

echo "🔎 Verifying artifacts..."
for artifact in dist/index.js dist/index.cjs dist/index.d.ts dist/index.d.cts; do
  [[ ! -f ${artifact} ]] && echo "❌ build artifact missing: ${artifact}" >&2 && exit 1
done

echo "🏃 Verifying ESM and CJS runtime exports..."
node --input-type=module -e "import { Hasher, Slugger } from './dist/index.js'; const s = new Slugger(); if (s.slugify('Build Proof') !== 'build-proof' || (await s.namespacedKey('Build Proof', 'ESM').unwrap()) !== 'build-proof:esm' || (await new Hasher().sha256('abc')) !== 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') process.exit(1)"
node -e "const { Hasher, Slugger } = require('./dist/index.cjs'); const s = new Slugger(); if (s.slugify('Build Proof') !== 'build-proof') process.exit(1); Promise.all([s.namespacedKey('Build Proof', 'CJS').unwrap(), new Hasher().sha256('abc')]).then(([k, h]) => { if (k !== 'build-proof:cjs' || h !== 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') process.exit(1) }).catch(() => process.exit(1))"

echo "✅ Built dist/index.{js,cjs,d.ts,d.cts}"
