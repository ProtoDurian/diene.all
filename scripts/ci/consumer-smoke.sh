#!/usr/bin/env bash
set -euo pipefail

# The node-owned consumer fixture: a throwaway package that `bun add`s the
# library, then proves `import`, `require()` and the TypeScript types of both
# conditions resolve. With no argument it consumes this tree's packed tarball;
# pass a registry spec (e.g. @atomicloud/diene.result@1.0.3) to consume a real
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
{ "name": "diene-result-consumer-fixture", "private": true, "version": "0.0.0" }
JSON
cat >"${work}/tsconfig.json" <<JSON
{
  "compilerOptions": {
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "strict": true,
    "noEmit": true,
    "types": []
  },
  "include": ["*.mts", "*.cts"]
}
JSON
cat >"${work}/esm.mjs" <<JS
import { Ok } from '${name}';
import { expectOk } from '${name}/test-helper';
if ((await expectOk(Ok(1).map((value) => value + 1))) !== 2) throw new Error('ESM import returned the wrong value');
JS
cat >"${work}/cjs.cjs" <<JS
const { Ok } = require('${name}');
const { expectOk } = require('${name}/test-helper');
expectOk(Ok(1).map((value) => value + 1)).then((value) => {
  if (value !== 2) throw new Error('CJS require returned the wrong value');
});
JS
cat >"${work}/types-esm.mts" <<TS
import { Ok, type Result } from '${name}';
import { expectOk } from '${name}/test-helper';
const result: Result<number, string> = Ok<number, string>(1);
const value: Promise<number> = expectOk(result);
export { value };
TS
cat >"${work}/types-cjs.cts" <<TS
import { Ok, type Result } from '${name}';
import { expectOk } from '${name}/test-helper';
const result: Result<number, string> = Ok<number, string>(1);
const value: Promise<number> = expectOk(result);
export { value };
TS

echo "📥 bun add ${spec}..."
(cd "${work}" && bun add --no-progress "${spec}")

echo "🔎 import, require() and types..."
(cd "${work}" && node esm.mjs && node cjs.cjs && "${tsc}" -p tsconfig.json)

echo "✅ consumer fixture: ${spec} installs; import, require() and both type conditions resolve"
