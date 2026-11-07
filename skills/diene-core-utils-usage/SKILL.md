---
name: diene-core-utils-usage
description: Use when consuming @atomicloud/diene.core-utils for slugs and keys, timing, fuzzy matching, bounded concurrency, stable records, hashing, dedupe, explicit-root path joins, or C0 Temporal wire codecs.
---

Import classes from `@atomicloud/diene.core-utils`. Each is stateless: create
one (`new Slugger()`) or inject it, then call its methods.

- `Slugger`: `slugify` for identifiers; `namespacedKey` returns a `Result`, so
  handle the `err` branch instead of calling `unwrap`.
- `Timing.sleep`/`noop`, `FuzzyMatcher.fuzzyIncludes` (case-insensitive
  substring only), `ConcurrencyMapper.mapWithConcurrency` with a limit chosen
  for the downstream resource.
- `RecordTools.isRecord` before record access, `stableConfig` before comparison
  or hashing, `Hasher.sha256`, and `array.filter(new Deduper().unique)`.
- `SafePath.safeJoin(root, ...)`: pure, explicit absolute root, never the cwd;
  returns `Result<string, VfsError>`. Do file I/O through the interfaces
  package's `VirtualFileSystem`.
- `WireDateCodec` at a transport boundary only: `parse*`/`format*` for date
  `YYYY-MM-DD`, time `HH:mm:ss`, UTC RFC 3339 instant, ISO 8601 duration and
  IANA timezone, returning `Result<…, WireDateError>`.

This package has TestHelper=NO; `pls test:meta` is a no-op. Read
[patterns.md](patterns.md) for examples and for how to create this lib's
TestHelper if a real need appears.
