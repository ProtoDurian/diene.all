# Utilities in Go

## Libraries: the standard library, then `samber/lo`

Reach for the standard library first: `slices`, `maps`, `strings` and `cmp`
cover sorting, searching, cloning and comparing. Use `github.com/samber/lo`
(v1.53.0, pinned in `go.mod`) only for what the standard library lacks:
map/filter/reduce, grouping, set operations, case conversion and the like.

```bash
go get github.com/samber/lo@v1.53.0
```

```go
import (
	"cmp"
	"maps"
	"slices"
	"strings"

	"github.com/samber/lo"
)
```

| Need                            | Use                                               |
| ------------------------------- | ------------------------------------------------- |
| contains, index, sort, min, max | `slices`                                          |
| clone, compare, insert, delete  | `slices`, `maps`                                  |
| map keys and values             | `maps.Keys`, `maps.Values` with `slices.Collect`  |
| map, filter, reduce, find       | `lo.Map`, `lo.Filter`, `lo.Reduce`, `lo.Find`     |
| groupBy, keyBy, uniq, flatten   | `lo.GroupBy`, `lo.KeyBy`, `lo.Uniq`, `lo.Flatten` |
| difference, intersection, union | `lo.Difference`, `lo.Intersect`, `lo.Union`       |
| case conversion, truncate       | `lo.CamelCase`, `lo.SnakeCase`, `lo.Ellipsis`     |
| once                            | `sync.OnceValue`, `sync.OnceValues`               |
| debounce, throttle              | `lo.NewDebounce`, `lo.NewThrottle`                |

## Collections

### contains, index (`slices`)

```go
slices.Contains(tags, "go") // bool
slices.Index(tags, "go")    // -1 if absent
slices.ContainsFunc(users, func(user User) bool { return user.Age > 30 })
```

### sortBy, orderBy (`slices`, `cmp`)

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
	return cmp.Or(cmp.Compare(b.Age, a.Age), cmp.Compare(a.Name, b.Name))
})

sorted := slices.Sorted(slices.Values(tags)) // a sorted copy
```

`slices.Sort` and `slices.SortFunc` sort in place. Clone first unless you own
the slice.

### map, filter, reduce (`lo`)

The standard library has none of these. `lo` callbacks also receive the index;
ignore it with `_`.

```go
names := lo.Map(users, func(user User, _ int) string { return user.Name })

active := lo.Filter(users, func(user User, _ int) bool { return user.Active })

total := lo.Reduce(items, func(sum int, item Item, _ int) int {
	return sum + item.Price
}, 0)

emails := lo.FilterMap(users, func(user User, _ int) (string, bool) {
	return user.Email, user.Email != ""
})
```

### find

```go
admin, ok := lo.Find(users, func(user User) bool { return user.Role == "admin" })
if !ok {
	return User{}, ErrNoAdmin
}

i := slices.IndexFunc(users, func(user User) bool { return user.Role == "admin" })
```

### groupBy, keyBy, countBy

```go
byRole := lo.GroupBy(users, func(user User) string { return user.Role })
// map[string][]User

byID := lo.KeyBy(users, func(user User) string { return user.ID })
// map[string]User; a later duplicate key wins

perRole := lo.CountValuesBy(users, func(user User) string { return user.Role })
// map[string]int
```

### uniq

`lo.Uniq` keeps the first occurrence and the original order. `slices.Compact`
only drops adjacent duplicates, so it needs sorted input.

```go
lo.Uniq([]string{"b", "a", "b"}) // [b a]

uniqueUsers := lo.UniqBy(users, func(user User) string { return user.Email })

slices.Compact(slices.Sorted(slices.Values(ids))) // sorted and unique
```

### chunk, flatten

```go
for batch := range slices.Chunk(ids, 100) {
	if err := store.DeleteMany(ctx, batch); err != nil {
		return fmt.Errorf("delete batch: %w", err)
	}
}

batches := lo.Chunk(ids, 100) // [][]string, when you need the slices themselves

flat := lo.Flatten([][]int{{1, 2}, {3, 4}}) // [1 2 3 4]
allTags := lo.FlatMap(posts, func(post Post, _ int) []string { return post.Tags })
```

### difference, intersection, union

```go
onlyLeft, onlyRight := lo.Difference([]int{1, 2, 3, 4}, []int{2, 4, 5}) // [1 3], [5]
lo.Intersect([]int{1, 2, 3}, []int{2, 3, 4})                            // [2 3]
lo.Union([]int{1, 2}, []int{2, 3})                                      // [1 2 3]
lo.Without([]string{"a", "b", "c"}, "b")                                // [a c]
```

### min, max, sum, clamp

```go
slices.Max(prices) // panics on an empty slice: check len first
slices.MinFunc(users, func(a, b User) int { return cmp.Compare(a.Age, b.Age) })
max(a, b, c) // builtin

lo.Sum([]int{1, 2, 3, 4}) // 10
lo.SumBy(items, func(item Item) int { return item.Price })
lo.Clamp(10, 1, 5) // 5
```

### clone, equal, concat, reverse

```go
copied := slices.Clone(tags)
slices.Equal(a, b)
all := slices.Concat(first, second, third)
slices.Reverse(all) // in place
```

## Maps

Map iteration order is random. Sort the keys whenever order is visible
(output, hashing, tests).

```go
roles := slices.Sorted(maps.Keys(byRole))

copied := maps.Clone(settings)
maps.Copy(copied, overrides) // overrides win
maps.DeleteFunc(copied, func(_ string, value string) bool { return value == "" })
maps.Equal(a, b)

public := lo.PickByKeys(settings, []string{"theme", "locale"})
safe := lo.OmitByKeys(settings, []string{"apiToken"})
counts := lo.MapValues(byRole, func(users []User, _ string) int { return len(users) })
```

### pick, omit on structs

A struct does not need pick or omit. Declare the response type with the fields
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

## Strings

```go
strings.Fields("  hello   world ")            // [hello world]
strings.Join([]string{"notes", "hello"}, ":") // "notes:hello"
strings.TrimSpace("  x  ")
strings.EqualFold("Go", "GO") // true
key, value, ok := strings.Cut("name=alice", "=")

lo.CamelCase("order_id")                    // "orderId"
lo.SnakeCase("InProgress")                  // "in_progress"
lo.KebabCase("helloWorld")                  // "hello-world"
lo.PascalCase("hello world")                // "HelloWorld"
lo.Capitalize("hello world")                // "Hello World"
lo.Ellipsis("hello world this is long", 15) // "hello world..."
```

Build long strings with `strings.Builder`, not `+=` in a loop.

## Pointers

Optional wire fields are pointers. `lo` converts both ways:

```go
req := UpdateUserReq{Bio: lo.ToPtr("hello")}
bio := lo.FromPtrOr(req.Bio, "") // the fallback when the field was omitted
```

## Functions

| Need     | Use                                                                  |
| -------- | -------------------------------------------------------------------- |
| once     | `sync.OnceValue(func() T)`, `sync.OnceValues(func() (T, error))`     |
| memoize  | `sync.OnceValue` for one value; an injected cache adapter for many   |
| debounce | `lo.NewDebounce(wait, fn)`, which returns `debounce` and `cancel`    |
| throttle | `lo.NewThrottle(interval, fn)`, which returns `throttle` and `reset` |

```go
save, cancel := lo.NewDebounce(300*time.Millisecond, func() {
	flusher.Flush(ctx)
})
defer cancel()
save()
save() // only one Flush runs, 300ms after the last call
```

## Best Practices

### Utility Calls Live Inside a Service

Utility calls are the body of an injectable service's method. They never
become a `util` package, and never hide in an unexported function.

```go
// lib/blog/post/tags.go
type TagNormalizer struct{}

func NewTagNormalizer() TagNormalizer {
	return TagNormalizer{}
}

func (TagNormalizer) Normalize(raw []string) []string {
	tags := lo.Map(raw, func(tag string, _ int) string {
		return strings.ToLower(strings.TrimSpace(tag))
	})
	return lo.Uniq(lo.Compact(tags))
}
```

```go
// lib/blog/post/service.go
type Service struct {
	repo Repository
	tags TagNormalizer
}

func NewService(repo Repository, tags TagNormalizer) Service {
	return Service{repo: repo, tags: tags}
}
```

```text
// WRONG
lib/util/slices.go
lib/common/helpers.go

// RIGHT - one focused type, exported method, black-box tests
lib/blog/post/tags.go
tests/unit/blog/post/tags_test.go
```

### Prefer the Standard Library

```go
// WRONG - lo for something slices already does
lo.Contains(tags, "go")
lo.IndexOf(tags, "go")

// RIGHT
slices.Contains(tags, "go")
slices.Index(tags, "go")
```

### Never `lo.Must` on Runtime Input

`lo.Must` panics on an error. Return the error instead, and keep `Must` for
values fixed at compile time.

```go
// WRONG - a bad request crashes the process
limit := lo.Must(strconv.Atoi(raw))

// RIGHT
limit, err := strconv.Atoi(raw)
if err != nil {
	return Page{}, fmt.Errorf("limit %q: %w", raw, err)
}
```

### Keep Chains Short

Name each intermediate slice instead of nesting three `lo` calls. A plain `for`
loop is fine when it reads better than the closures.
