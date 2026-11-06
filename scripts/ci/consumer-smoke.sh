#!/usr/bin/env bash
set -euo pipefail

# The node-owned consumer fixture: a throwaway package that `bun add`s the
# library, then proves `import`, `require()` and the TypeScript types of both
# conditions resolve. With no argument it consumes this tree's packed tarball;
# pass a registry spec (e.g. @atomicloud/diene.problems@2.0.0) to consume a real
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
{ "name": "diene-problems-consumer-fixture", "private": true, "version": "0.0.0" }
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
uri="https://errors.example/docs/pichu/nitroso/zinc/api/v1/entity_not_found"
portal="{ scheme: 'https', host: 'errors.example', landscape: 'pichu', platform: 'nitroso', service: 'zinc', module: 'api' }"
cat >"${work}/esm.mjs" <<JS
import { GenericProblemCatalog } from '${name}';
import { ProblemTestHelper } from '${name}/test-helper';
const registry = new GenericProblemCatalog().createGenericProblemRegistry(${portal});
if (registry.require('entity_not_found').type !== '${uri}') throw new Error('ESM import built the wrong type URI');
const helper = new ProblemTestHelper();
helper.expectProblem(helper.buildProblemFromRegistry(registry, 'unauthorized', { data: {} })).toBe(registry.require('unauthorized'));
JS
cat >"${work}/cjs.cjs" <<JS
const { GenericProblemCatalog } = require('${name}');
const { ProblemTestHelper } = require('${name}/test-helper');
const registry = new GenericProblemCatalog().createGenericProblemRegistry(${portal});
if (registry.require('entity_not_found').type !== '${uri}') throw new Error('CJS require built the wrong type URI');
const helper = new ProblemTestHelper();
helper.expectProblem(helper.buildProblemFromRegistry(registry, 'unauthorized', { data: {} })).toBe(registry.require('unauthorized'));
JS
for ext in mts cts; do
  cat >"${work}/types.${ext}" <<TS
import { GenericProblemCatalog, type Problem, type RegisteredProblem } from '${name}';
import { ProblemTestHelper } from '${name}/test-helper';
const registry = new GenericProblemCatalog().createGenericProblemRegistry(${portal});
const entry: RegisteredProblem = registry.require('entity_not_found');
const problem: Problem = new ProblemTestHelper().buildProblem(entry, { data: { entityType: 'Note', id: '1' } });
export { problem };
TS
done

echo "📥 bun add ${spec}..."
(cd "${work}" && bun add --no-progress "${spec}")

echo "🔎 import, require() and types..."
(cd "${work}" && node esm.mjs && node cjs.cjs && "${tsc}" -p tsconfig.json)

echo "✅ consumer fixture: ${spec} installs; import, require() and both type conditions resolve"
