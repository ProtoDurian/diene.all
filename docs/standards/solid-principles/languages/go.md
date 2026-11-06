# SOLID Principles in Go

## Folder Structure

```text
lib/                      # domain layer: ports and stateless services
  note/
    key.go
    service.go
internal/                 # optional: focused packages with an exported, tested surface
  <name>/
adapters/                 # adapter layer: port implementations
  kv/
    redis.go
cmd/
  go-base/
    main.go               # composition root
```

## Single Responsibility (SRP)

Each type has one reason to change. In the sample, how a key is spelled and how
a note is stored change for different reasons, so they are different types.

```go
// lib/note/key.go - changes when the key format changes
type KeyComposer struct {
	namespace string
}

func (keys KeyComposer) Compose(key string) string {
	return keys.namespace + ":" + key
}
```

```go
// lib/note/service.go - changes when the note workflow changes
type Service struct {
	store Store
	keys  KeyComposer
}
```

### No Hidden Logic

Unexported fields are acceptable; unexported logic is not. An unexported
function or method is a hidden dependency: callers cannot see it in a
signature, and black-box tests cannot reach it.

```go
// WRONG - the slug rule hides inside Service
func (service Service) Create(ctx context.Context, title string, body string) (Note, error) {
	slug := service.slugify(title)
	// ...
}

func (Service) slugify(title string) string {
	return strings.Join(strings.Fields(strings.ToLower(title)), "-")
}
```

```go
// RIGHT - the rule is an exported method on an injected collaborator
func NewService(store Store, keys KeyComposer) Service

func (service Service) Create(ctx context.Context, title string, body string) (Note, error) {
	value := Note{Slug: service.keys.Slug(title), Body: body}
	// ...
}
```

When the helper does not belong to an existing collaborator, move it into a
cohesive `internal/<name>` package with an exported API and its own black-box
tests. `internal/` keeps it out of other modules without hiding it from your
own tests.

## Open/Closed (OCP)

Extend behaviour by adding an implementation of a port, not by editing the
service.

```go
type Store interface {
	Save(ctx context.Context, key string, value string) error
	Load(ctx context.Context, key string) (string, error)
}
```

```go
// adapters/kv/redis.go
func (store *RedisStore) Save(ctx context.Context, key string, value string) error {
	return store.client.Set(ctx, key, value, 0).Err()
}
```

```go
// adapters/kv/memory.go - a new backend; note.Service is unchanged
type MemoryStore struct {
	values map[string]string
	mu     *sync.Mutex
}

func NewMemoryStore() MemoryStore {
	return MemoryStore{values: map[string]string{}, mu: &sync.Mutex{}}
}

func (store MemoryStore) Save(_ context.Context, key string, value string) error {
	store.mu.Lock()
	defer store.mu.Unlock()
	store.values[key] = value
	return nil
}

func (store MemoryStore) Load(_ context.Context, key string) (string, error) {
	store.mu.Lock()
	defer store.mu.Unlock()
	return store.values[key], nil
}
```

Prefer a small interface with a struct behind it over passing function values
(`func(ctx, key) error`). A struct can carry configuration, has a name in stack
traces and error messages, and grows a second method without changing every
signature.

## Liskov Substitution (LSP)

Every implementation of a port must keep the same contract: after `Save(k, v)`,
`Load(k)` returns `v`; a failure comes back as an `error`, never a panic or a
silent zero value. The sample checks the same save-then-load round trip twice:
in the unit tier through a hand-written fake (`tests/unit/note`), and in the
integration tier against real Redis (`tests/int/kv`).

```go
// WRONG - satisfies the interface, breaks the contract
func (ReadOnlyStore) Save(context.Context, string, string) error {
	panic("read only")
}
```

If an implementation cannot honour a method, the interface is too wide. Split
it (ISP) rather than panic.

## Interface Segregation (ISP)

`RedisStore` has three methods, but `note.Store` names only the two the service
calls. `Close` belongs to whoever owns the connection: the composition root.

```go
// WRONG - the domain is forced to know about connection lifetime
type Store interface {
	Save(ctx context.Context, key string, value string) error
	Load(ctx context.Context, key string) (string, error)
	Close() error
}
```

```go
// RIGHT - each consumer declares what it calls
// lib/note/service.go
type Store interface {
	Save(ctx context.Context, key string, value string) error
	Load(ctx context.Context, key string) (string, error)
}

// a read-only consumer elsewhere
type Loader interface {
	Load(ctx context.Context, key string) (string, error)
}
```

`*kv.RedisStore` satisfies both without changing, because Go interfaces are
implicit.

## Dependency Inversion (DIP)

The domain owns the abstraction; the adapter depends on nothing in the domain
to implement it; the composition root connects them.

```text
cmd/go-base  ──►  adapters/kv  (concrete RedisStore)
     │
     └──────►  lib/note       (Store port, Service)

lib/note imports neither cmd nor adapters.
```

```go
// cmd/go-base/main.go
store := kv.NewRedisStore(args[1])
service := note.NewService(store, note.NewKeyComposer("notes"))
```

### Visible + Fixed

Everything a type needs is in its constructor signature, and it never changes
afterwards.

```go
// WRONG - not visible, not fixed
var defaultStore Store

func (service Service) Create(ctx context.Context, title string, body string) (Note, error) {
	return Note{}, defaultStore.Save(ctx, title, body)
}

// RIGHT
func NewService(store Store, keys KeyComposer) Service {
	return Service{store: store, keys: keys}
}
```

## No Singletons

- No package-level variables holding clients, loggers or configuration.
- No `init()` (rejected by `gochecknoinits`).
- No package-level functions with business logic that callers cannot swap.
  Make them methods on an injected type.

```go
// WRONG - a decree from the universe
slog.Info("note created", "slug", value.Slug)

// RIGHT - a request to a collaborator
type Logger interface {
	Info(msg string, args ...any)
}

func NewService(store Store, keys KeyComposer, logger Logger) Service
```

`*slog.Logger` already satisfies that `Logger`, so the root passes
`slog.New(handler)` and tests pass a spy.

## Temporal Coupling

```go
// WRONG - Build fails unless SetTable ran first
type QueryBuilder struct {
	table   string
	columns []string
}

func (builder *QueryBuilder) SetTable(table string) { builder.table = table }

func (builder *QueryBuilder) Build() (Query, error) {
	if builder.table == "" {
		return Query{}, errors.New("table not set")
	}
	// ...
}
```

```go
// RIGHT - the constructor demands everything Build needs
func NewQueryBuilder(table string, columns []string) QueryBuilder

func (builder QueryBuilder) Build() Query
```

```go
// WRONG - totals depend on earlier AddItem calls
func (service *OrderService) AddItem(item Item)
func (service *OrderService) Total() Money

// RIGHT - all data flows through parameters
func (service OrderService) Total(items []Item) Money
```

## Quick Checklist

- [ ] One reason to change per type.
- [ ] Unexported fields only; every function and method with logic is exported.
- [ ] Ports are small, consumer-owned interfaces.
- [ ] `lib/` never imports `adapters/` or `cmd/`.
- [ ] No globals, singletons or `init()`; constructors take every dependency.
