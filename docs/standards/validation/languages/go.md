# Validation in Go

## Library: none (standard library only)

Go validation uses plain constructors and the `errors` package. Struct-tag
validators (`go-playground/validator` and similar) are not used: they hide rules
in strings the compiler cannot check, and they still hand you an unparsed
`string` afterwards.

```go
import (
	"errors"
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"
)
```

## Parse, Don't Validate

A validator answers "is this string OK?" and then throws the answer away. A
parser returns a new type that can only hold valid values, so later code never
asks again.

```go
// WRONG - every caller must remember to call it, and still holds a string
func IsValidSlug(raw string) bool

// RIGHT - holding a Slug is the proof
func NewSlug(raw string) (Slug, error)
```

### Value Objects

```go
// lib/note/slug.go
package note

var ErrInvalidSlug = errors.New("invalid slug")

var slugPattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

type Slug struct {
	value string
}

func NewSlug(raw string) (Slug, error) {
	if len(raw) > 64 || !slugPattern.MatchString(raw) {
		return Slug{}, fmt.Errorf("%w: %q", ErrInvalidSlug, raw)
	}
	return Slug{value: raw}, nil
}

func (slug Slug) String() string {
	return slug.value
}
```

- The field is unexported, so no other package can build `Slug{value: "Bad!"}`.
  The zero value `Slug{}` is still possible; treat it as "absent".
- `type Slug string` is weaker: `note.Slug("Bad!")` compiles anywhere.
- A compiled `regexp` is immutable, so a package-level pattern is fine. Mutable
  package state is not.

### Sentinel and Typed Errors

Use a sentinel (`ErrInvalidSlug`) when callers only need to know which rule
failed. Use a typed error when they also need data from it.

```go
// lib/note/errors.go
type FieldError struct {
	Field string
	Err   error
}

func (fieldErr *FieldError) Error() string {
	return fieldErr.Field + ": " + fieldErr.Err.Error()
}

func (fieldErr *FieldError) Unwrap() error {
	return fieldErr.Err
}
```

Callers match with `errors.Is` and `errors.As`, never with `==` or a string
compare, because both see through `%w` wrapping:

```go
if errors.Is(err, note.ErrInvalidSlug) {
	// the slug rule failed, however deeply the error was wrapped
}

var fieldErr *note.FieldError
if errors.As(err, &fieldErr) {
	// fieldErr.Field names the input that failed
}
```

### Several Fields at Once

Report every invalid field in one response, not the first one only. Collect the
failures and combine them with `errors.Join`.

```go
// lib/note/draft.go
var ErrEmptyBody = errors.New("body is empty")

var ErrBodyTooLong = errors.New("body is longer than 10000 characters")

type Draft struct {
	Slug Slug
	Body string
}

func NewDraft(rawSlug string, rawBody string) (Draft, error) {
	slug, slugErr := NewSlug(rawSlug)

	body := strings.TrimSpace(rawBody)
	var bodyErr error
	switch {
	case body == "":
		bodyErr = ErrEmptyBody
	case utf8.RuneCountInString(body) > 10000:
		bodyErr = ErrBodyTooLong
	}

	var errs []error
	if slugErr != nil {
		errs = append(errs, &FieldError{Field: "slug", Err: slugErr})
	}
	if bodyErr != nil {
		errs = append(errs, &FieldError{Field: "body", Err: bodyErr})
	}
	if len(errs) > 0 {
		return Draft{}, errors.Join(errs...)
	}
	return Draft{Slug: slug, Body: body}, nil
}
```

`errors.Is` and `errors.As` search every branch of a joined error, but
`errors.As` stops at the first match. To list every field, unwrap the join:

```go
var joined interface{ Unwrap() []error }
if errors.As(err, &joined) {
	for _, each := range joined.Unwrap() {
		var fieldErr *note.FieldError
		if errors.As(each, &fieldErr) {
			problems = append(problems, FieldProblem{Field: fieldErr.Field, Message: fieldErr.Err.Error()})
		}
	}
}
```

### Cross-Field Invariants

A rule that spans fields belongs to the constructor of the type that owns both.

```go
var ErrWindowOrder = errors.New("window ends before it starts")

type Window struct {
	Start time.Time
	End   time.Time
}

func NewWindow(start time.Time, end time.Time) (Window, error) {
	if end.Before(start) {
		return Window{}, fmt.Errorf("%w: %s < %s", ErrWindowOrder, end.Format(time.RFC3339), start.Format(time.RFC3339))
	}
	return Window{Start: start.UTC(), End: end.UTC()}, nil
}
```

## Validation at Boundaries

| Layer   | Checks                                                   | Fails with                       |
| ------- | -------------------------------------------------------- | -------------------------------- |
| Adapter | shape: body size, JSON syntax, unknown or missing fields | transport error (400, exit 2)    |
| Domain  | invariants: slug format, body length, window order       | domain error from `lib/`         |
| Adapter | mapping: domain error to status code and response body   | `errors.Is` / `errors.As` switch |

### Shape in the Adapter

The request type mirrors the wire, not the domain. Pointer fields tell a missing
field apart from an empty one.

```go
// adapters/api/note/req.go
type CreateNoteReq struct {
	Slug *string `json:"slug"`
	Body *string `json:"body"`
}
```

```go
// adapters/api/note/controller.go
func (controller Controller) Create(writer http.ResponseWriter, request *http.Request) {
	decoder := json.NewDecoder(http.MaxBytesReader(writer, request.Body, 64<<10))
	decoder.DisallowUnknownFields()

	var req CreateNoteReq
	if err := decoder.Decode(&req); err != nil {
		controller.problems.Write(writer, http.StatusBadRequest, err)
		return
	}
	if req.Slug == nil || req.Body == nil {
		controller.problems.Write(writer, http.StatusBadRequest, ErrMissingField)
		return
	}

	draft, err := note.NewDraft(*req.Slug, *req.Body)
	if err != nil {
		controller.problems.Write(writer, http.StatusUnprocessableEntity, err)
		return
	}

	created, err := controller.service.Publish(request.Context(), draft)
	if err != nil {
		controller.problems.Write(writer, http.StatusInternalServerError, err)
		return
	}
	controller.responses.Write(writer, http.StatusCreated, NewNoteRes(created))
}
```

The adapter decides what "malformed request" means for its transport. It does
not re-check the slug rule: `note.NewDraft` owns that.

### Invariants in the Domain

The domain service accepts the parsed type, so it cannot receive an invalid
value.

```go
// WRONG - every caller can pass anything
func (service Service) Publish(ctx context.Context, slug string, body string) (Note, error)

// RIGHT - the signature demands a parsed Draft
func (service Service) Publish(ctx context.Context, draft Draft) (Note, error)
```

## Best Practices

### Return Errors, Never Panic

```go
// WRONG - a bad request crashes the process
slug := MustNewSlug(raw)

// RIGHT - the caller decides
slug, err := NewSlug(raw)
if err != nil {
	return Note{}, err
}
```

`Must...` helpers are only for constants known at compile time, such as
`regexp.MustCompile` with a literal.

### Write Messages for the Caller

```go
// WRONG
errors.New("validation failed")

// RIGHT - the rule and the offending value
fmt.Errorf("%w: %q", ErrInvalidSlug, raw)
```

Never echo secrets (passwords, tokens) back in an error message.

### Do

- Parse once, at the edge, into a domain type.
- Keep each rule in exactly one constructor.
- Export the sentinel and typed errors so adapters can map them.

### Don't

- Pass `map[string]any`, raw `string` IDs or half-checked structs into `lib/`.
- Validate the same rule in the adapter and in the domain.
- Match errors by comparing `err.Error()` strings.
