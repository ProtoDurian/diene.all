# Testing in Go

## Framework: `testing` + testcontainers-go

The standard `testing` package runs every tier, and `gotestsum` drives it. No
assertion or mocking library is used. Integration and SIT tests start real
dependencies with testcontainers-go.

```bash
go get github.com/testcontainers/testcontainers-go
```

```go
import (
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)
```

## Test Tiers

| Tier        | Location      | Subject                                | Coverage profile                   |
| ----------- | ------------- | -------------------------------------- | ---------------------------------- |
| Unit        | `tests/unit/` | `lib/**` only, with hand-written fakes | `reports/unit/coverage.out`        |
| Integration | `tests/int/`  | `adapters/**` against real Redis       | `reports/integration/coverage.out` |
| SIT         | `tests/sit/`  | the compiled `dist/go-base` binary     | none                               |

```bash
task test:unit
task test:unit:coverage
task test:int:coverage
task build && task test:sit
task test:unit:watch
```

Coverage scopes are include lists in `.config/go-base.coverage.yaml`, passed to
`-coverpkg`. Each tier must reach 100% of its own scope. Never add an exclusion
list: if code cannot be covered from its tier, it is in the wrong layer.

## Black-Box Packages

Every `*_test.go` file declares `package <name>_test` and imports the package
under test like any other client. `export_test.go` is banned: it would expose
internals to tests only. The pre-commit hook enforces both (golangci-lint's
`testpackage` linter and `scripts/validate/go-black-box-tests.sh`).

```go
// tests/unit/note/note_test.go
package note_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-base/lib/note"
)
```

```go
// WRONG - white-box package reaches unexported fields
package note

// WRONG - test-only door into the package
// lib/note/export_test.go
var ComposeForTest = composeKey
```

If a test needs something that is not exported, the code under test is hiding a
dependency. Export it from a focused package or inject it (see
[SOLID in Go](../../solid-principles/languages/go.md)).

## Arrange / Act / Assert

House rule: every test body has up to three blocks, each opened by its marker
comment and separated by a blank line. Leave out a block that would be empty,
together with its marker. Name the values `subject`, `input`, `expected` and
`actual`.

```go
func TestKeyComposerCompose(t *testing.T) {
	t.Parallel()

	// Arrange
	subject := note.NewKeyComposer("notes")
	input := "hello-world"

	// Act
	actual := subject.Compose(input)

	// Assert
	if expected := "notes:hello-world"; actual != expected {
		t.Fatalf("Compose(%q) = %q, want %q", input, actual, expected)
	}
}
```

Call `t.Parallel()` in unit tests. They share nothing, so order cannot matter.

## Assertions

Plain `if` statements. Report what was called, what came back and what was
wanted, in that order.

| Check           | Write                                                                   |
| --------------- | ----------------------------------------------------------------------- |
| equality        | `if actual != expected { t.Fatalf("F(%q) = %q, want %q", …) }`          |
| struct equality | `if actual != expected` on comparable structs, else `reflect.DeepEqual` |
| slices / maps   | `slices.Equal(actual, expected)`, `maps.Equal(actual, expected)`        |
| no error        | `if err != nil { t.Fatalf("F() error = %v", err) }`                     |
| sentinel error  | `if !errors.Is(err, note.ErrInvalidSlug) { … }`                         |
| typed error     | `var fieldErr *note.FieldError; if !errors.As(err, &fieldErr) { … }`    |

Use `t.Fatalf` when the rest of the test cannot run, and `t.Errorf` to report
several independent failures from one run.

## Table-Driven Tests

One case can pass by luck. Triangulate with a table and run each row as a
subtest.

```go
func TestKeyComposerSlug(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name     string
		input    string
		expected string
	}{
		{name: "lowercases", input: "Hello", expected: "hello"},
		{name: "joins words", input: "Hello World", expected: "hello-world"},
		{name: "collapses spaces", input: "  Hello   World  ", expected: "hello-world"},
		{name: "empty", input: "", expected: ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			// Arrange
			subject := note.NewKeyComposer("notes")

			// Act
			actual := subject.Slug(tc.input)

			// Assert
			if actual != tc.expected {
				t.Fatalf("Slug(%q) = %q, want %q", tc.input, actual, tc.expected)
			}
		})
	}
}
```

Go 1.22+ gives each loop iteration its own `tc`, so parallel subtests no longer
need `tc := tc`.

## Hand-Written Fakes

Implement the port directly in the test package. No mocking framework.

```go
type FakeStore struct {
	Values  map[string]string
	SaveErr error
	LoadErr error
}

func (store *FakeStore) Save(_ context.Context, key string, value string) error {
	store.Values[key] = value
	return store.SaveErr
}

func (store *FakeStore) Load(_ context.Context, key string) (string, error) {
	return store.Values[key], store.LoadErr
}
```

```go
func TestServiceRoundTrip(t *testing.T) {
	t.Parallel()

	// Arrange
	store := &FakeStore{Values: map[string]string{}}
	subject := note.NewService(store, note.NewKeyComposer("notes"))

	// Act
	created, createErr := subject.Create(t.Context(), "Hello World", "from the domain")
	actual, loadErr := subject.Load(t.Context(), created.Slug)

	// Assert
	if createErr != nil || loadErr != nil {
		t.Fatalf("Create() error = %v, Load() error = %v", createErr, loadErr)
	}
	if expected := (note.Note{Slug: "hello-world", Body: "from the domain"}); actual != expected {
		t.Fatalf("Load() = %#v, want %#v", actual, expected)
	}
	if got := store.Values["notes:hello-world"]; got != "from the domain" {
		t.Fatalf("stored value = %q, want %q", got, "from the domain")
	}
}
```

The fake's exported fields are the spy: preset errors to drive failure paths,
then read `Values` to check what the subject wrote.

## Spies

```go
// Record calls
type SpyLogger struct {
	Messages []string
}

func (logger *SpyLogger) Log(message string) {
	logger.Messages = append(logger.Messages, message)
}
// Assert: slices.Equal(logger.Messages, []string{"created hello-world"})

// Count calls and fail every time
type FailingStore struct {
	Calls int
}

func (store *FailingStore) Save(context.Context, string, string) error {
	store.Calls++
	return errors.New("store unavailable")
}
// Assert: store.Calls == 3
```

A fake that is not safe for concurrent use must not be shared between parallel
tests. Build a new one in each test's Arrange block.

## Integration Test: Testcontainers

Integration tests prove an adapter against the real dependency. They do not
fake the thing they exist to prove.

```go
// tests/int/kv/redis_test.go
package kv_test

func TestRedisStore(t *testing.T) {
	// Arrange
	ctx := context.Background()
	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: testcontainers.ContainerRequest{
			Image:        "redis:7.4.5-alpine",
			ExposedPorts: []string{"6379/tcp"},
			WaitingFor:   wait.ForLog("Ready to accept connections"),
		},
		Started: true,
	})
	if err != nil {
		t.Fatalf("start Redis container: %v", err)
	}
	t.Cleanup(func() {
		if terminateErr := container.Terminate(ctx); terminateErr != nil {
			t.Errorf("terminate Redis container: %v", terminateErr)
		}
	})

	endpoint, err := container.Endpoint(ctx, "")
	if err != nil {
		t.Fatalf("resolve Redis endpoint: %v", err)
	}
	subject := kv.NewRedisStore(endpoint)

	// Act
	if saveErr := subject.Save(ctx, "notes:integration", "connected"); saveErr != nil {
		t.Fatalf("Save() error = %v", saveErr)
	}
	actual, err := subject.Load(ctx, "notes:integration")

	// Assert
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if actual != "connected" {
		t.Fatalf("Load() = %q, want %q", actual, "connected")
	}
	if err := subject.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
}
```

- Pin the image tag (`redis:7.4.5-alpine`), never `latest`.
- Wait on a readiness signal (`wait.ForLog`, `wait.ForListeningPort`), never on a
  sleep.
- `t.Context()` is canceled before cleanups run. Terminate the container with a
  context that outlives the test, as above.

## SIT: The Compiled Artifact

SIT runs the binary that ships, from the outside. `task build` writes
`dist/go-base` first.

```go
// tests/sit/cli/cli_test.go
// Act
// #nosec G204 -- the executable is fixed; only the isolated testcontainer endpoint is dynamic.
output, err := exec.CommandContext(ctx, "../../../dist/go-base", "note", endpoint, "Sample Journey", "connected").CombinedOutput()

// Assert
if err != nil {
	t.Fatalf("run compiled artifact: %v\n%s", err, output)
}
if actual, expected := string(output), "sample-journey=connected\n"; actual != expected {
	t.Fatalf("compiled artifact output = %q, want %q", actual, expected)
}
```

## Best Practices

- Test through exported behaviour only. A refactor that keeps behaviour must not
  break a test.
- One behaviour per test function or table row; name it after that behaviour.
- Deterministic: inject the clock, randomness and IDs; never sleep.
- Use `t.TempDir()`, `t.Setenv()` and `t.Context()` instead of hand-rolled
  setup and teardown.
- Fakes live in the test package that uses them. Never ship test doubles from
  `lib/` or `adapters/`.
