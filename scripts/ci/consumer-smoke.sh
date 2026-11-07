#!/usr/bin/env bash
set -euo pipefail

# The node-owned consumer fixture: a throwaway package that `bun add`s the
# library, then proves `import`, `require()` and the TypeScript types of both
# conditions resolve. With no argument it consumes this tree's packed tarball;
# pass a registry spec (e.g. @atomicloud/diene.interfaces@1.0.1) to consume a real
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
{ "name": "diene-interfaces-consumer-fixture", "private": true, "version": "0.0.0" }
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
import { PortError } from '${name}';
import { InMemoryTerminal } from '${name}/test-helper';
const terminal = new InMemoryTerminal();
terminal.close();
const failure = await terminal.write({ channel: 'stdout', text: 'x' }).unwrapErr();
if (!(failure instanceof PortError) || failure.code !== 'closed') throw new Error('ESM import returned the wrong failure');
JS
cat >"${work}/cjs.cjs" <<JS
const { PortError } = require('${name}');
const { InMemoryTerminal } = require('${name}/test-helper');
const terminal = new InMemoryTerminal();
terminal.close();
terminal.write({ channel: 'stdout', text: 'x' }).unwrapErr().then((failure) => {
  if (!(failure instanceof PortError) || failure.code !== 'closed') throw new Error('CJS require returned the wrong failure');
});
JS
cat >"${work}/types-esm.mts" <<TS
import { PortError, type Terminal, type TerminalError } from '${name}';
import { InMemoryTerminal } from '${name}/test-helper';
const terminal: Terminal = new InMemoryTerminal();
const failure: TerminalError = new PortError('terminal', 'closed', 'write', 'consumer');
export { failure, terminal };
TS
cat >"${work}/types-cjs.cts" <<TS
import { PortError, type Terminal, type TerminalError } from '${name}';
import { InMemoryTerminal } from '${name}/test-helper';
const terminal: Terminal = new InMemoryTerminal();
const failure: TerminalError = new PortError('terminal', 'closed', 'write', 'consumer');
export { failure, terminal };
TS

echo "📥 bun add ${spec}..."
(cd "${work}" && bun add --no-progress "${spec}")

echo "🔎 import, require() and types..."
(cd "${work}" && node esm.mjs && node cjs.cjs && "${tsc}" -p tsconfig.json)

echo "✅ consumer fixture: ${spec} installs; import, require() and both type conditions resolve"
