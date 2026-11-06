#!/usr/bin/env bash
set -euo pipefail

# The node-owned consumer fixture: a throwaway package that `bun add`s the
# library, then proves `import`, `require()` and the TypeScript types of both
# conditions resolve. With no argument it consumes this tree's packed tarball;
# pass a registry spec (e.g. @atomicloud/diene.bun-lib@1.4.0) to consume a real
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
{ "name": "bun-lib-consumer-fixture", "private": true, "version": "0.0.0" }
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
import { Slugger } from '${name}';
if (new Slugger().slugify('Consumer Proof') !== 'consumer-proof') throw new Error('ESM import returned the wrong slug');
JS
cat >"${work}/cjs.cjs" <<JS
const { Slugger } = require('${name}');
if (new Slugger().slugify('Consumer Proof') !== 'consumer-proof') throw new Error('CJS require returned the wrong slug');
JS
cat >"${work}/types-esm.mts" <<TS
import { Slugger } from '${name}';
const key: string = new Slugger().slugify('Consumer Proof');
export { key };
TS
cat >"${work}/types-cjs.cts" <<TS
import { Slugger } from '${name}';
const key: string = new Slugger().slugify('Consumer Proof');
export { key };
TS

echo "📥 bun add ${spec}..."
(cd "${work}" && bun add --no-progress "${spec}")

echo "🔎 import, require() and types..."
(cd "${work}" && node esm.mjs && node cjs.cjs && "${tsc}" -p tsconfig.json)

echo "✅ consumer fixture: ${spec} installs; import, require() and both type conditions resolve"
