# Domain-Driven Design in Go

## Folder Structure

Domain packages live under `lib/` and import nothing from transport or storage.
Adapters live under `adapters/`. `cmd/<name>` wires them together.

```text
lib/                      # pure domain: no HTTP, SQL, Redis or env imports
  note/                   # domain package, named in the ubiquitous language
    key.go                # KeyComposer
    service.go            # Note, Store port, Service
adapters/                 # impure code
  kv/
    redis.go              # RedisStore satisfies note.Store
cmd/
  go-base/
    main.go               # composition root
tests/
  unit/note/              # lib/** only
  int/kv/                 # adapters/** against real Redis
  sit/cli/                # the compiled binary
```

When a service has several bounded contexts, nest them:

```text
lib/
  blog/                   # bounded context
    post/                 # domain package: package post
      structures.go       # Record, Principal, Post
      service.go          # Service, Repository port
      errors.go           # ErrNotFound, NotFoundError
    author/
    authorpage/           # view that needs both post and author
  identity/               # different bounded context
    user/
adapters/
  blog/
    post/
      api/                # req.go, res.go, mapper.go, controller.go
      data/               # repo.go, mapper.go
```

Name packages after domain nouns (`post`, `note`), never after layers
(`models`, `types`). The package name is part of every identifier, so drop the
stutter: `post.Record`, not `post.PostRecord`.

## Record (Pure Data, No Identity)

```go
// lib/blog/post/structures.go
package post

type Record struct {
	Title       string
	Description string
	Tags        []string
}
```

```go
// lib/blog/author/structures.go
package author

type Record struct {
	Name        string
	DateOfBirth civil.Date
}
```

Domain structs carry no `json`, `db` or `redis` tags. Wire names belong to the
adapter's own request, response and row types.

## Multiple Records per Entity

Split fields that change at different rates into separate records:

```go
// lib/identity/user/structures.go
package user

type Record struct {
	DisplayName string
	Bio         string
	AvatarURL   string
}

type ImmutableRecord struct {
	Email     string
	CreatedAt time.Time
}

type SyncRecord struct {
	StripeCustomerID string
	GitHubID         *string
	LastSyncAt       time.Time
}
```

Use a pointer (or a dedicated optional type) only for a value that is genuinely
optional. Do not use the empty string to mean "absent".

## Principal (Record + Identity)

```go
type Principal struct {
	ID     string
	Record Record
}
```

```go
// lib/identity/user/structures.go
type Principal struct {
	ID        string
	Record    Record
	Immutable ImmutableRecord
	Sync      SyncRecord
}
```

The sample in this repository is the smallest principal there is: `Slug` is the
identity and `Body` is the record.

```go
// lib/note/service.go
type Note struct {
	Slug string
	Body string
}
```

## Model (Assembled View)

```go
// lib/blog/post/structures.go
type Post struct {
	Principal Principal
	Author    author.Principal
}
```

Go forbids import cycles. `post` already imports `author`, so the author view
cannot live in `author`. Assemble it in a package that imports both:

```go
// lib/blog/authorpage/structures.go
package authorpage

type Author struct {
	Principal author.Principal
	Posts     []post.Principal
}
```

## Ports (Consumer-Owned Interfaces)

The domain package declares the interface it needs, and only the methods it
calls. Adapters satisfy it implicitly; they never import the domain to say so.

```go
// lib/note/service.go
type Store interface {
	Save(ctx context.Context, key string, value string) error
	Load(ctx context.Context, key string) (string, error)
}
```

```go
// adapters/kv/redis.go
type RedisStore struct {
	client *redis.Client
}

func (store *RedisStore) Save(ctx context.Context, key string, value string) error {
	return store.client.Set(ctx, key, value, 0).Err()
}

func (store *RedisStore) Load(ctx context.Context, key string) (string, error) {
	return store.client.Get(ctx, key).Result()
}
```

`adapters/kv` does not need to import `lib/note` to satisfy the port. The
compiler checks the fit where `cmd/go-base/main.go` passes a `*kv.RedisStore` to
`note.NewService`. Dependencies point inward only: an adapter may import `lib/`
(for its errors and structs), but `lib/` never imports an adapter.

## Repository Port (CRUD Blessed Path)

```go
// lib/blog/post/service.go
type Repository interface {
	Search(ctx context.Context, params Search) ([]Principal, error)
	Get(ctx context.Context, id string) (Post, error)
	Create(ctx context.Context, record Record) (Post, error)
	Update(ctx context.Context, id string, record Record) (Post, error)
	Delete(ctx context.Context, id string) error
}
```

## Domain Service (Same Shape)

The service is a concrete struct with the same CRUD shape as the repository. A
caller that wants to fake it (an HTTP controller, for example) declares its own
interface next to itself.

```go
type Service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return Service{repo: repo}
}

func (service Service) Get(ctx context.Context, id string) (Post, error) {
	return service.repo.Get(ctx, id)
}
```

The real sample follows the same pattern, with key composition injected as a
collaborator:

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

## Search Params

```go
type Search struct {
	TitleContains string
	Tags          []string
	Limit         int
	Offset        int
}
```

## Domain Errors

"Not found" is a domain outcome, not a `nil` pointer. Declare it in the domain
package; adapters translate their driver's error into it.

```go
// lib/blog/post/errors.go
var ErrNotFound = errors.New("post not found")

type NotFoundError struct {
	ID string
}

func (notFound *NotFoundError) Error() string {
	return "post not found: " + notFound.ID
}

func (*NotFoundError) Unwrap() error {
	return ErrNotFound
}
```

```go
// adapters/blog/post/data/repo.go
func (repo Repo) Get(ctx context.Context, id string) (post.Post, error) {
	var row PostRow
	err := repo.db.QueryRowContext(ctx, selectPost, id).Scan(&row.ID, &row.Title, &row.AuthorID)
	if errors.Is(err, sql.ErrNoRows) {
		return post.Post{}, &post.NotFoundError{ID: id}
	}
	if err != nil {
		return post.Post{}, err
	}
	return repo.mapper.ToDomain(row), nil
}
```

Callers then match with `errors.Is(err, post.ErrNotFound)` or
`errors.As(err, &notFound)`, whichever adapter produced the error.

The sample's `RedisStore.Load` still returns go-redis errors unchanged, so a
missing key reaches the domain as `redis.Nil`. Add the same translation there
once the domain needs to tell "missing" apart from "failed".

## Quick Checklist

- [ ] `lib/**` imports no transport, storage or configuration package.
- [ ] Records, principals and models are plain structs with exported fields.
- [ ] Ports are small interfaces declared in the package that calls them.
- [ ] Adapters map wire and row types to domain structs, and driver errors to
      domain errors.
- [ ] Every fallible operation returns `(T, error)`.
