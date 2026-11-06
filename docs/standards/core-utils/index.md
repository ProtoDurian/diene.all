# Core utilities

`@atomicloud/diene.core-utils` is the Bun family's small, deterministic value
layer. Import from the package root. It owns common normalization, timing,
collection, hashing, path-value and C0 temporal-codec behavior; configuration
loading and deep merge belong to `@atomicloud/diene.config`, and filesystem
effects belong to the System/VFS ports of `@atomicloud/diene.interfaces`.

The package depends on the published `@atomicloud/diene.result@1.0.2` and
`@atomicloud/diene.interfaces@1.0.0`. Fallible values use the former's
async-native `Result<T, E>` rather than a throw path.

## Shape

Every member is a method on a stateless class with no constructor dependencies,
so `new Slugger()` is cheap and an instance can be shared or injected. `src/index.ts`
only re-exports `src/lib/*`; there are no free functions and no adapters.

| Class               | Methods                                                           |
| ------------------- | ----------------------------------------------------------------- |
| `Slugger`           | `slugify`, `namespacedKey`                                        |
| `Timing`            | `sleep`, `noop`                                                   |
| `FuzzyMatcher`      | `fuzzyIncludes`                                                   |
| `ConcurrencyMapper` | `mapWithConcurrency`                                              |
| `RecordTools`       | `isRecord`, `stableConfig`                                        |
| `Hasher`            | `sha256`                                                          |
| `Deduper`           | `unique` (a bound field: `array.filter(deduper.unique)`)          |
| `SafePath`          | `safeJoin`                                                        |
| `WireDateCodec`     | `parse*` / `format*` for Date, Time, DateTime, Duration, TimeZone |

## Keys and simple utilities

`slugify` applies NFKD normalization, removes combining marks, lowercases and
produces a kebab-case identifier; it is not for display text.
`namespacedKey(namespace, key)` returns
`Result<string, NamespacedKeyValidationError>`: a part that normalizes to empty
is an `Err`, never a throw. Handle both branches instead of calling `unwrap`.

`sleep(seconds)` rejects a negative or non-finite delay with a `RangeError`;
`noop` is the intentional no-op callback. `fuzzyIncludes` is a case-insensitive
substring test, not ranking, collation or authorization.

## Collections, records and digests

`mapWithConcurrency` keeps at most `concurrency` mapper calls in flight and
returns results in input order; pick the limit from the downstream resource.
`isRecord` narrows to a non-null, non-array object. `stableConfig` returns a
key-sorted deep clone for repeatable comparison or hash input, and throws a
`TypeError` on a cycle; it does not validate a schema. `unique` keeps the first
occurrence under SameValueZero. `sha256` returns a lowercase hex digest of a
UTF-8 string; serialize a `stableConfig` result before hashing structured values.

## Path values

`SafePath.safeJoin(root, ...segments)` is pure: it performs no I/O and never
reads the current working directory. `root` must be a canonical absolute VFS
path (checked with the interfaces package's `validateVfsPath`), segments resolve
with POSIX rules, and a result outside `root` is an `Err`. Every failure is a
`PortError<'vfs'>` with code `invalid-input` and operation `safeJoin`, and an
`Ok` value is a valid path for a `VirtualFileSystem`. Read and write files
through that port, not through this package.

## C0 wire-date codecs

`WireDateCodec` translates between Temporal domain values and the transport forms
of C0 §1 Serialization, the cross-language serialization contract; the table
below is that contract's complete wire rule set. It follows the repository's
[date/time standard](../datetime/index.md). These are wire values, not display
formats.

| Domain value         | Canonical wire form                | Methods                            |
| -------------------- | ---------------------------------- | ---------------------------------- |
| `Temporal.PlainDate` | `YYYY-MM-DD`                       | `parseDate` / `formatDate`         |
| `Temporal.PlainTime` | `HH:mm:ss`                         | `parseTime` / `formatTime`         |
| `Temporal.Instant`   | RFC 3339 UTC instant ending in `Z` | `parseDateTime` / `formatDateTime` |
| `Temporal.Duration`  | ISO 8601 duration                  | `parseDuration` / `formatDuration` |
| `WireTimeZone`       | canonical IANA identifier          | `parseTimeZone` / `formatTimeZone` |

Every `parse*` method, and every `format*` method that can meet an
unrepresentable value, returns `Result<…, WireDateError>`; `formatDuration` is
total and returns a string. `WireDateError` extends `RangeError` and names the
`form` that failed. Parsing rejects non-canonical spellings; formatting emits the
one canonical spelling. Fractional instant seconds are kept, while `HH:mm:ss`
rejects a sub-second time rather than dropping precision. Fixed offsets and
abbreviations are not timezones.

## TestHelper and the meta tier

This package has **TestHelper=NO**. Every member is a cheap, deterministic value
operation with no consumer-injected port to fake, and stock equality covers its
outputs. The inherited `pls test:meta` stays a no-op and no `meta` coverage is
uploaded. Across the library family a real TestHelper's meta tier proves
**assert-the-asserter** (each custom assertion accepts a known-good case and
rejects a known-bad one), **contract parity** (a fake behaves like the real
implementation) and **fixture invariants** (builders cannot emit invalid values).

The integration tier is kept but empty (no `src/adapters`, no
`tests/integration`), and `pls test:int` is a green no-op until both exist.

See the shipped [usage skill](../../../skills/diene-core-utils-usage/SKILL.md)
for consumer patterns and the procedure for revisiting the TestHelper decision.
