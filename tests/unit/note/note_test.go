package note_test

import (
	"context"
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-base/lib/note"
)

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

func TestKeyComposerSlug(t *testing.T) {
	t.Parallel()

	// Arrange
	keys := note.NewKeyComposer("notes")

	// Act
	got := keys.Slug("Hello   World")

	// Assert
	if want := "hello-world"; got != want {
		t.Fatalf("Slug() = %q, want %q", got, want)
	}
}

func TestKeyComposerCompose(t *testing.T) {
	t.Parallel()

	// Arrange
	keys := note.NewKeyComposer("notes")

	// Act
	got := keys.Compose("hello-world")

	// Assert
	if want := "notes:hello-world"; got != want {
		t.Fatalf("Compose() = %q, want %q", got, want)
	}
}

func TestServiceRoundTrip(t *testing.T) {
	t.Parallel()

	// Arrange
	store := &FakeStore{Values: map[string]string{}}
	service := note.NewService(store, note.NewKeyComposer("notes"))

	// Act
	created, createErr := service.Create(context.Background(), "Hello World", "from the domain")
	loaded, loadErr := service.Load(context.Background(), created.Slug)

	// Assert
	if createErr != nil || loadErr != nil {
		t.Fatalf("Create() error = %v, Load() error = %v", createErr, loadErr)
	}
	if want := (note.Note{Slug: "hello-world", Body: "from the domain"}); loaded != want {
		t.Fatalf("Load() = %#v, want %#v", loaded, want)
	}
	if got := store.Values["notes:hello-world"]; got != "from the domain" {
		t.Fatalf("stored value = %q, want %q", got, "from the domain")
	}
}

func TestServiceErrors(t *testing.T) {
	t.Parallel()

	// Arrange
	want := errors.New("store unavailable")
	store := &FakeStore{Values: map[string]string{}, SaveErr: want, LoadErr: want}
	service := note.NewService(store, note.NewKeyComposer("notes"))

	// Act
	_, createErr := service.Create(context.Background(), "Failure", "body")
	_, loadErr := service.Load(context.Background(), "failure")

	// Assert
	if !errors.Is(createErr, want) {
		t.Fatalf("Create() error = %v, want %v", createErr, want)
	}
	if !errors.Is(loadErr, want) {
		t.Fatalf("Load() error = %v, want %v", loadErr, want)
	}
}
