# Functional Practices in Go

## Immutability

Go has no `readonly`, so immutability is a convention the code keeps:

- Domain objects use value receivers and never write their own fields after
  `New...`.
- Transformations return a new value instead of changing their argument.
- Slices and maps are references. Copying a struct copies the slice header, not
  the elements, so clone before you change one.

```go
type Post struct {
	Title string
	Tags  []string
}

// WRONG - appends into the caller's backing array when it has spare capacity
func (Tagger) WithTag(post Post, tag string) Post {
	post.Tags = append(post.Tags, tag)
	return post
}

// RIGHT - the caller's Post is untouched
func (Tagger) WithTag(post Post, tag string) Post {
	post.Tags = append(slices.Clone(post.Tags), tag)
	return post
}
```

The same applies to slices you return: hand back `slices.Clone(internal)` if
the caller must not change what you hold.

## Pure Functions

A method is pure when its receiver's fields are fixed and it touches nothing
outside its arguments. Both `KeyComposer` methods in the sample are pure:

```go
// lib/note/key.go
func (KeyComposer) Slug(value string) string {
	return strings.Join(strings.Fields(strings.ToLower(value)), "-")
}

func (keys KeyComposer) Compose(key string) string {
	return keys.namespace + ":" + key
}
```

Clocks, randomness, filesystems and network clients make a method impure. Pass
them in through interfaces so the impurity is visible and swappable:

```go
// WRONG - reads the machine clock and global randomness
func (Stamper) Stamp(body string) StampedNote {
	return StampedNote{ID: rand.Text(), Body: body, CreatedAt: time.Now()}
}

// RIGHT - every input is in the signature or the constructor
type Stamper struct {
	clock Clock
	ids   IDSource
}

func (stamper Stamper) Stamp(body string) StampedNote {
	return StampedNote{ID: stamper.ids.New(), Body: body, CreatedAt: stamper.clock.Now().UTC()}
}
```

### Deterministic Output

Map iteration order is random by design. Any output built from a map must sort
first.

```go
// WRONG - a different order on every run
for role, users := range byRole {
	fmt.Fprintf(out, "%s=%d\n", role, len(users))
}

// RIGHT
for _, role := range slices.Sorted(maps.Keys(byRole)) {
	fmt.Fprintf(out, "%s=%d\n", role, len(byRole[role]))
}
```

## Total Functions

Every fallible operation returns `(T, error)`. The signature is the contract:
if it can fail, the error is in the return type.

- Never `panic` for an expected failure (bad input, missing record, network
  error). Panics are for programmer bugs only.
- Handle every error. `errcheck` rejects a dropped error; discard one only with
  an explicit `_ =` where nothing useful can be done, as `cmd/go-base/main.go`
  does for writes to stderr.
- On error, return the zero value of `T` and never use it.

```go
// lib/note/service.go
func (service Service) Load(ctx context.Context, slug string) (Note, error) {
	body, err := service.store.Load(ctx, service.keys.Compose(slug))
	if err != nil {
		return Note{}, err
	}
	return Note{Slug: slug, Body: body}, nil
}
```

## Railway Oriented Programming

Go has no `Result` type. The early `return` on error is the railway: each step
runs only if every earlier step succeeded, and the first failure leaves the
function.

```go
// lib/note/service.go
func (service Service) Create(ctx context.Context, title string, body string) (Note, error) {
	value := Note{Slug: service.keys.Slug(title), Body: body}
	if err := service.store.Save(ctx, service.keys.Compose(value.Slug), value.Body); err != nil {
		return Note{}, err
	}
	return value, nil
}
```

```go
func (publisher Publisher) Publish(ctx context.Context, title string, body string) (Note, error) {
	created, err := publisher.notes.Create(ctx, title, body)
	if err != nil {
		return Note{}, err
	}
	if err := publisher.notifier.Announce(ctx, created); err != nil {
		return Note{}, err
	}
	return created, nil
}
```

Do not build `Map`/`AndThen` combinators to imitate a `Result` type. The
straight-line version is the idiom and the linters understand it.

### Wrapping Errors

Wrap only when the context changes what a caller can understand or do. Always
use `%w` so `errors.Is` and `errors.As` still see the cause.

```go
// WRONG - noise; the caller learns nothing new
return Note{}, fmt.Errorf("error: %w", err)

// WRONG - %v cuts the chain; errors.Is(err, redis.Nil) is now false
return Note{}, fmt.Errorf("load note %q: %v", slug, err)

// RIGHT - adds the slug the caller asked for
return Note{}, fmt.Errorf("load note %q: %w", slug, err)
```

### Error Mapping Between Layers

Each layer turns the errors below it into its own terms. The adapter maps domain
errors to its transport:

```go
// adapters/api/note/problems.go
func (Problems) Status(err error) int {
	switch {
	case errors.Is(err, note.ErrInvalidSlug), errors.Is(err, note.ErrEmptyBody):
		return http.StatusUnprocessableEntity
	case errors.Is(err, note.ErrNotFound):
		return http.StatusNotFound
	default:
		return http.StatusInternalServerError
	}
}
```

## Grouping, Not Encapsulation

Group related behaviour as exported methods on one type; do not hide it. Every
method of `KeyComposer` is exported and tested from `package note_test`. A type
is cohesive because its methods change together, not because some of them are
secret.

## Folder Structure

```text
lib/                      # pure: deterministic, dependencies injected
  note/
adapters/                 # impure: clocks, Redis, HTTP, filesystem
  kv/
cmd/
  go-base/                # the only place impure adapters are built
```
