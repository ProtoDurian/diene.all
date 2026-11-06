# Stateless OOP with DI in Go

## Folder Structure

```text
lib/                      # domain: structures, ports, stateless services
  note/
    key.go                # KeyComposer (object, no dependencies)
    service.go            # Note (structure), Store (port), Service (object)
adapters/                 # impure implementations of the ports
  kv/
    redis.go              # RedisStore
cmd/
  go-base/
    main.go               # composition root: the only place that calls New... for adapters
```

## Structures (Pure Data)

Exported fields, no behaviour, no dependencies. Copy them freely.

```go
// lib/note/service.go
type Note struct {
	Slug string
	Body string
}
```

## Interfaces (Dependency Contracts)

Declared by the consumer, as small as its calls. Implementations satisfy them
implicitly.

```go
// lib/note/service.go
type Store interface {
	Save(ctx context.Context, key string, value string) error
	Load(ctx context.Context, key string) (string, error)
}
```

## Stateless Objects

An object is a struct whose fields are its dependencies and configuration. The
fields are set once by the constructor and never written again.

```go
// lib/note/key.go
type KeyComposer struct {
	namespace string
}

func NewKeyComposer(namespace string) KeyComposer {
	return KeyComposer{namespace: namespace}
}

func (KeyComposer) Slug(value string) string {
	return strings.Join(strings.Fields(strings.ToLower(value)), "-")
}

func (keys KeyComposer) Compose(key string) string {
	return keys.namespace + ":" + key
}
```

```go
// lib/note/service.go
type Service struct {
	store Store
	keys  KeyComposer
}

func NewService(store Store, keys KeyComposer) Service {
	return Service{store: store, keys: keys}
}

func (service Service) Load(ctx context.Context, slug string) (Note, error) {
	body, err := service.store.Load(ctx, service.keys.Compose(slug))
	if err != nil {
		return Note{}, err
	}
	return Note{Slug: slug, Body: body}, nil
}
```

- **Value receivers** on domain objects: a method gets a copy, so it cannot
  write state back.
- **Unexported fields** are fine: they are fixed configuration, visible in the
  constructor signature. Unexported logic is not (see
  [SOLID in Go](../../solid-principles/languages/go.md)).
- **Return the concrete type** from `New...` (`Service`, not an interface). The
  consumer chooses the interface it needs.
- **Request data flows through parameters.** `ctx`, `slug` and `body` arrive in
  each call and leave in the return value.

```go
// WRONG - request state kept on the object
type Service struct {
	store    Store
	lastSlug string
}

func (service *Service) Create(ctx context.Context, title string, body string) error {
	service.lastSlug = slugOf(title)
	return service.store.Save(ctx, service.lastSlug, body)
}
```

The pointer receiver is the warning sign: it exists only to mutate. Two
concurrent requests now race on `lastSlug`.

## Constructor Injection

Every dependency appears in the `New...` signature. Nothing is fetched from a
global, an environment variable or a package-level client inside a method.

```go
// WRONG - hidden, unswappable dependencies
func (service Service) Create(ctx context.Context, title string, body string) (Note, error) {
	client := redis.NewClient(&redis.Options{Addr: os.Getenv("REDIS_ADDR")})
	log.Printf("creating %s", title)
	// ...
}

// RIGHT - visible in the signature, fixed after construction
func NewService(store Store, keys KeyComposer) Service
```

No package-level singletons and no `init()` functions (the `gochecknoinits`
linter rejects them). A value that every caller shares is built once in
`cmd/<name>` and passed down.

## Entry Point Wiring

`cmd/go-base/main.go` is the composition root. It builds concrete adapters with
plain `New...` calls and passes them inward. There is no DI container.

```go
// cmd/go-base/main.go
case "note":
	if len(args) != 4 {
		_, _ = fmt.Fprintln(stderr, Usage)
		return 2
	}
	store := kv.NewRedisStore(args[1])
	service := note.NewService(store, note.NewKeyComposer("notes"))
	value, err := service.Create(context.Background(), args[2], args[3])
```

```go
func main() {
	os.Exit(Execute(os.Args[1:], os.Stdout, os.Stderr))
}
```

- `main` only reads process state (`os.Args`, `os.Stdout`) and hands it to
  `Execute`. `Execute` takes plain arguments and `io.Writer`s, so it can be
  driven with buffers instead of a real terminal.
- The root owns the lifetime of what it builds: it calls `store.Close()`, which
  the domain's `Store` port deliberately does not expose.
- Reading configuration (flags, environment) happens here too. Convert it into
  typed values before passing it to a constructor.

## Adapter (Impure Implementation)

```go
// adapters/kv/redis.go
type RedisStore struct {
	client *redis.Client
}

func NewRedisStore(address string) *RedisStore {
	return &RedisStore{client: redis.NewClient(&redis.Options{Addr: address})}
}

func (store *RedisStore) Save(ctx context.Context, key string, value string) error {
	return store.client.Set(ctx, key, value, 0).Err()
}

func (store *RedisStore) Load(ctx context.Context, key string) (string, error) {
	return store.client.Get(ctx, key).Result()
}

func (store *RedisStore) Close() error {
	return store.client.Close()
}
```

An adapter that owns a resource handle returns a pointer: copying a struct that
wraps a connection pool would make two owners of one `Close`. The handle is
still fixed after construction; the pointer receiver does not license request
state.

## Quick Checklist

- [ ] Structures: exported fields, no methods with logic.
- [ ] Objects: dependencies in unexported fields, set only by `New...`.
- [ ] Domain objects use value receivers; resource-owning adapters use pointers.
- [ ] No globals, singletons or `init()`.
- [ ] `cmd/<name>` is the only place adapters are constructed.
