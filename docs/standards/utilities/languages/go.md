# Utilities in Go

## Library: the standard library

Go 1.26's standard library covers what Lodash covers in TypeScript: generic
`slices` and `maps`, `strings`, `cmp` for ordering, and `iter` for lazy
sequences. Reach for `golang.org/x/...` only when the standard library has no
equivalent, and add nothing else for helpers. `samber/lo` and similar packages
are not used.

```go
import (
	"cmp"
	"iter"
	"maps"
	"slices"
	"strings"
)
```

## Collections: `slices`

### map, filter, reduce

There are no `Map`/`Filter` helpers. A loop is the idiom, and it is clearer than
a chain of closures.

```go
names := make([]string, 0, len(users))
for _, user := range users {
	names = append(names, user.Name)
}

active := slices.DeleteFunc(slices.Clone(users), func(user User) bool {
	return !user.Active
})

total := 0
for _, item := range items {
	total += item.Price
}
```

`slices.DeleteFunc` reuses its argument's backing array. Clone first unless you
own the slice.

### find, contains

```go
slices.Contains(tags, "go")                                  // bool
slices.Index(tags, "go")                                     // -1 if absent
i := slices.IndexFunc(users, func(user User) bool { return user.Role == "admin" })
slices.ContainsFunc(users, func(user User) bool { return user.Age > 30 })
```

### sortBy, orderBy

Sort with a comparison function. `cmp.Or` chains keys: it returns the first
non-zero comparison.

```go
slices.SortFunc(users, func(a, b User) int {
	return cmp.Or(
		cmp.Compare(a.Role, b.Role),
		cmp.Compare(a.Name, b.Name),
	)
})

// descending age, then ascending name
slices.SortStableFunc(users, func(a, b User) int {
	return cmp.Or(
		cmp.Compare(b.Age, a.Age),
		strings.Compare(a.Name, b.Name),
	)
})

slices.Sort(tags)
slices.IsSorted(tags)
```

`slices.Sort` sorts in place. Use `slices.Sorted(slices.Values(tags))` for a
sorted copy.

### uniq

```go
unique := slices.Compact(slices.Sorted(slices.Values(ids))) // sort, then drop adjacent duplicates
```

For uniqueness by key, or to keep the original order, use a set:

```go
seen := make(map[string]struct{}, len(users))
uniqueUsers := make([]User, 0, len(users))
for _, user := range users {
	if _, dup := seen[user.Email]; dup {
		continue
	}
	seen[user.Email] = struct{}{}
	uniqueUsers = append(uniqueUsers, user)
}
```

### groupBy

```go
byRole := make(map[string][]User)
for _, user := range users {
	byRole[user.Role] = append(byRole[user.Role], user)
}
```

### chunk, concat, reverse, min, max

```go
for batch := range slices.Chunk(ids, 100) {
	if err := store.DeleteMany(ctx, batch); err != nil {
		return err
	}
}

all := slices.Concat(first, second, third)
slices.Reverse(all)

slices.Max(prices)
slices.MinFunc(users, func(a, b User) int { return cmp.Compare(a.Age, b.Age) })
max(a, b, c) // builtin
```

`slices.Max` and `slices.Min` panic on an empty slice. Check `len` first.

### equal, clone, insert, delete

```go
slices.Equal(a, b)
copied := slices.Clone(tags)
tags = slices.Insert(tags, 0, "first")
tags = slices.Delete(tags, 1, 2)
```

### difference, intersection, union

There are no set helpers. Build a lookup map from one side and loop the other.

```go
exclude := make(map[string]struct{}, len(removed))
for _, id := range removed {
	exclude[id] = struct{}{}
}
kept := slices.DeleteFunc(slices.Clone(ids), func(id string) bool {
	_, drop := exclude[id]
	return drop
})
```

## Maps: `maps`

Map iteration order is random. Sort the keys whenever order is visible (output,
hashing, tests).

```go
keys := slices.Sorted(maps.Keys(byRole))
for _, role := range keys {
	fmt.Fprintln(stdout, role, len(byRole[role]))
}

copied := maps.Clone(settings)
maps.Copy(copied, overrides) // overrides win
maps.DeleteFunc(copied, func(_ string, value string) bool { return value == "" })
maps.Equal(a, b)

lookup := maps.Collect(slices.All(names)) // index -> name
```

### pick, omit

Go structs do not need pick and omit. Declare the response type with the fields
you want and map into it:

```go
type UserRes struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}

res := UserRes{ID: user.ID, Name: user.Name, Email: user.Email}
```

### cloneDeep, merge

There is no deep clone or deep merge. Assigning a struct copies it, but its
slices and maps are still shared. Clone those fields yourself:

```go
copied := post
copied.Tags = slices.Clone(post.Tags)
```

## Strings: `strings`

```go
strings.Fields("  hello   world ")                 // ["hello" "world"]
strings.Join([]string{"notes", "hello"}, ":")      // "notes:hello"
strings.ToLower("Hello")
strings.TrimSpace("  x  ")
strings.EqualFold("Go", "GO")                      // true

key, value, ok := strings.Cut("name=alice", "=")
rest, found := strings.CutPrefix("notes:hello", "notes:")

strings.Repeat("-", 20)
fmt.Sprintf("%-10s|", "pad")                       // "pad       |"
```

`KeyComposer.Slug` in `lib/note/key.go` is the whole slug rule in one line of
standard library calls:

```go
strings.Join(strings.Fields(strings.ToLower(value)), "-")
```

Build long strings with `strings.Builder`, not `+=` in a loop:

```go
var builder strings.Builder
for _, line := range lines {
	builder.WriteString(line)
	builder.WriteByte('\n')
}
out := builder.String()
```

Lazy splitting (Go 1.24) avoids allocating the whole slice:

```go
for line := range strings.Lines(text) {
	if strings.TrimSpace(line) == "" {
		blank++
	}
}

for word := range strings.FieldsSeq(text) {
	if word == target {
		found = true
		break
	}
}
```

Each value from `strings.Lines` keeps its trailing `"\n"`.

### Case Conversion

`strings.Title` is deprecated. For human-readable casing use
`golang.org/x/text/cases`:

```go
import (
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

cases.Title(language.English).String("hello world") // "Hello World"
```

## Sequences: `iter`

`iter.Seq[V]` and `iter.Seq2[K, V]` are lazy sequences you can `range` over.
Return one when callers may stop early or the full slice would be large.

```go
func (repo PostRepo) All(ctx context.Context) iter.Seq2[Post, error] {
	return func(yield func(Post, error) bool) {
		rows, err := repo.db.QueryContext(ctx, "SELECT id, title FROM posts")
		if err != nil {
			yield(Post{}, err)
			return
		}
		defer rows.Close()
		for rows.Next() {
			var post Post
			if err := rows.Scan(&post.ID, &post.Title); err != nil {
				yield(Post{}, err)
				return
			}
			if !yield(post, nil) {
				return
			}
		}
		if err := rows.Err(); err != nil {
			yield(Post{}, err)
		}
	}
}

for post, err := range repo.All(ctx) {
	if err != nil {
		return err
	}
	if post.Title == wanted {
		break
	}
}
```

Stop as soon as `yield` returns `false`. Calling it again after that panics.

## Functions

| Lodash       | Go                                                               |
| ------------ | ---------------------------------------------------------------- |
| `once`       | `sync.OnceValue(func() T)`, `sync.OnceValues(func() (T, error))` |
| `memoize`    | `sync.OnceValue` for one value; an explicit map field for many   |
| `throttle`   | `golang.org/x/time/rate.Limiter`                                 |
| `debounce`   | `time.AfterFunc` and `Timer.Reset`                               |
| parallel map | `golang.org/x/sync/errgroup` with `SetLimit`                     |

```go
group, ctx := errgroup.WithContext(ctx)
group.SetLimit(8)
for _, id := range ids {
	group.Go(func() error {
		return store.Refresh(ctx, id)
	})
}
if err := group.Wait(); err != nil {
	return err
}
```

## Errors: `errors`

```go
errors.Is(err, note.ErrInvalidSlug)
errors.As(err, &fieldErr)
errors.Join(slugErr, bodyErr) // nil if every argument is nil
fieldErr, ok := errors.AsType[*note.FieldError](err) // Go 1.26
```

## Best Practices

### No Utility Bags

```text
// WRONG
lib/util/strings.go
lib/common/helpers.go

// RIGHT - one focused package, exported API, black-box tests
internal/slugify/slugify.go
tests/unit/slugify/slugify_test.go
```

A helper that only one package uses stays in that package as an exported method
on the type that needs it. A helper used by several packages gets its own
package named for what it does. Never hide helper logic in unexported functions.

### Prefer the Standard Library

```go
// WRONG - a dependency for one line
lo.Uniq(ids)

// RIGHT
slices.Compact(slices.Sorted(slices.Values(ids)))
```

### Write the Loop

If the standard library has no function for it, a short `for` loop is the Go
answer. Do not write a generic `Map`/`Filter`/`Reduce` package to avoid it.
