# Utility Libraries

Utility libraries provide common operations for collections, strings, objects, and functions. They reduce boilerplate code, improve readability, and are battle-tested.

This article builds on [Software Design Philosophy](../software-design-philosophy/index.md). The goal is to write less code by using proven utilities.

---

## Why Use Utility Libraries

### Reduce Code

Without utilities, common operations require repetitive code:

```typescript
// Manual implementation
function groupBy<T>(items: T[], key: (item: T) => string): Record<string, T[]> {
  return items.reduce(
    (acc, item) => {
      const k = key(item);
      if (!acc[k]) acc[k] = [];
      acc[k].push(item);
      return acc;
    },
    {} as Record<string, T[]>,
  );
}
```

With a utility library:

```text
grouped = groupBy(items, item -> item.category)
```

### Reduce Tests

Utility libraries are battle-tested. Don't retest library internals; still write tests for your business logic and integration behavior.

You don't need to test that the library correctly implements:

- Sorting algorithms
- Debounce/throttle behavior
- Deep cloning
- Object merging

### Improve Readability

Named utilities are self-documenting:

```text
-- Without utility
unique = empty list
seen   = empty set
for each s in items:
    if s not in seen:
        add s to seen
        append s to unique

-- With utility
unique = uniq(items)
```

---

## Categories of Utilities

### Collections

Operations on arrays, slices, and lists.

| Operation | Description                 |
| --------- | --------------------------- |
| map       | Transform each element      |
| filter    | Keep matching elements      |
| reduce    | Fold into single value      |
| find      | Find first matching element |
| groupBy   | Group elements by key       |
| sortBy    | Sort by property            |
| flatten   | Flatten nested arrays       |
| chunk     | Split into chunks           |
| uniq      | Remove duplicates           |
| zip/unzip | Combine/separate arrays     |

### Strings

String manipulation utilities.

| Operation       | Description                 |
| --------------- | --------------------------- |
| trim            | Remove whitespace           |
| case conversion | camelCase, snake_case, etc. |
| truncate        | Limit length with ellipsis  |
| template        | Interpolate values          |
| pad             | Pad to length               |
| split/join      | Split into array, join back |
| capitalize      | Uppercase first letter      |

### Objects

Object manipulation utilities.

| Operation   | Description                |
| ----------- | -------------------------- |
| pick        | Select properties          |
| omit        | Exclude properties         |
| merge       | Deep merge objects         |
| cloneDeep   | Deep clone object          |
| keys/values | Get property names/values  |
| entries     | Convert to key-value pairs |
| fromEntries | Convert pairs to object    |

### Functions

Function utilities.

| Operation | Description         |
| --------- | ------------------- |
| debounce  | Delay until pause   |
| throttle  | Limit rate of calls |
| memoize   | Cache results       |
| once      | Execute only once   |
| curry     | Partial application |
| compose   | Chain functions     |

---

## Choosing the Right Tool

Use the language's native collection features first. Reach for its utility
library only for operations the native features do not cover.

---

## Quick Checklist

**Before adding a utility function:**

- [ ] Check if native features suffice
- [ ] Check if utility library provides it
- [ ] Consider if the utility is actually needed
- [ ] Ensure tree-shakeable import

**When using utilities:**

- [ ] Import only what you need
- [ ] Use named imports for clarity
- [ ] Prefer functional style over loops
- [ ] Document complex transformations

---

## Language Implementations

Language bases add their implementation guides in their own branch deltas. This
shared standard defines only the language-agnostic contract.

## Related Articles

- [Software Design Philosophy](../software-design-philosophy/index.md) — Why write less code
- [Testing](../testing/index.md) — Testing with utility functions
- [Domain Modeling](../domain-driven-design/index.md) — Using utilities in domain logic
