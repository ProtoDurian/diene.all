# @atomicloud/diene.core-utils — patterns

## Keys and Result handling

```ts
import { Slugger } from '@atomicloud/diene.core-utils';

const slugger = new Slugger();
slugger.slugify('Customer Profile'); // customer-profile

const key = await slugger.namespacedKey('Customer Profile', 'Primary Email').match({
  ok: value => value,
  err: error => {
    throw new Error(`invalid cache key: ${error.field} ${error.reason}`);
  },
});
// customer-profile:primary-email
```

An empty normalized namespace or key is ordinary validation: choose a
caller-appropriate `err` branch rather than `unwrap()`.

## Injecting the classes

```ts
import { ConcurrencyMapper, Hasher, RecordTools } from '@atomicloud/diene.core-utils';

class ConfigFingerprint {
  constructor(
    private readonly records: RecordTools,
    private readonly hasher: Hasher,
  ) {}

  of(config: unknown): Promise<string> {
    return this.hasher.sha256(JSON.stringify(this.records.stableConfig(config)));
  }
}

const fingerprint = new ConfigFingerprint(new RecordTools(), new Hasher());
const outputs = await new ConcurrencyMapper().mapWithConcurrency(inputs, 4, input => work(input));
```

Pick a concurrency limit from the API, database or disk capacity. `stableConfig`
makes comparison and digest input repeatable; it does not validate a schema.

## Small helpers

```ts
import { Deduper, FuzzyMatcher, Timing } from '@atomicloud/diene.core-utils';

const names = ['a', 'a', 'b'].filter(new Deduper().unique); // ['a', 'b']
new FuzzyMatcher().fuzzyIncludes('Release Candidate', 'candidate'); // true
await new Timing().sleep(0.25);
```

`unique` is a bound field, so passing it unbound to `filter` is safe.

## Explicit-root paths

```ts
import { SafePath } from '@atomicloud/diene.core-utils';
import type { VirtualFileSystem } from '@atomicloud/diene.interfaces';

const safePath = new SafePath();
const read = (vfs: VirtualFileSystem, tenantId: string, documentId: string) =>
  safePath.safeJoin('/srv/app/uploads', tenantId, `${documentId}.json`).andThen(path => vfs.readFile(path));
```

`safeJoin` does no I/O and never reads the cwd. A relative or non-canonical root,
or a segment that escapes the root, is an `Err` carrying a
`PortError<'vfs'>` (`invalid-input`).

## C0 Temporal codecs

```ts
import { Temporal } from '@js-temporal/polyfill';
import { WireDateCodec } from '@atomicloud/diene.core-utils';

const wire = new WireDateCodec();

const date = await wire.formatDate(Temporal.PlainDate.from('2026-07-24')).unwrap(); // '2026-07-24'
const instant = await wire.parseDateTime('2026-07-24T09:30:00Z').match({
  ok: value => value,
  err: error => {
    throw new Error(`bad ${error.form}: ${error.message}`);
  },
});
const duration = wire.formatDuration(Temporal.Duration.from('PT15M')); // total: a plain string
const zone = await wire.parseTimeZone('Europe/London').unwrap(); // WireTimeZone
```

Accepted wire spellings: date `YYYY-MM-DD`, time `HH:mm:ss`, a UTC RFC 3339
instant ending in `Z` (written with exactly three fraction digits, read with 0-9), an ISO 8601
duration in canonical Temporal spelling, and a case-normalized IANA timezone id.
Never put localized dates, offsets or abbreviations such as `PST` on the wire.

## TestHelper: only when evidence changes the verdict

This package ships no TestHelper: consumers call deterministic value methods
directly and stock equality covers the outputs. Do not create a separate helper
package or another skill.

Re-open the decision only when a consumer-facing seam must be faked (for example
a newly added injectable clock) or the same nontrivial assertion repeats across
consumer suites. Then create this lib's TestHelper the bun-family way:

1. Add `src/test-helper/index.ts` (stateless classes, no free functions) and a
   `./test-helper` subpath export, as `@atomicloud/diene.interfaces` does; build
   it in `scripts/local/build.sh` and list its four `dist/test-helper.*` files in
   `scripts/ci/pkg-validate.sh`.
2. Keep test-framework dependencies out of the helper's runtime code.
3. Add `tests/meta/**` in the same change: assert-the-asserter, contract parity
   between each fake and its real counterpart, and fixture/builder invariants.
   `scripts/local/test-meta.sh` refuses a helper without meta tests.
4. Extend this skill rather than adding a new one.

Until then `pls test:meta` stays an inherited no-op and no `meta` coverage is
uploaded.
