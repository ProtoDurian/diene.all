package testhelper_test

// DOMAIN WIRING: replaceable Note sample TestHelper meta tests.
import (
	"context"
	"errors"
	"testing"

	"github.com/ProtoDurian/diene.go-lib/lib/note"
	"github.com/ProtoDurian/diene.go-lib/testhelper"
)

func TestMemoryStoreServesTheService(t *testing.T) {
	t.Parallel()

	// Arrange
	service := note.NewService(testhelper.NewMemoryStore(), note.NewKeyComposer("notes"))

	// Act
	created, err := service.Create(context.Background(), "Meta Contract", "consumer fake")
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	got, err := service.Load(context.Background(), created.Slug)
	// Assert
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if got != created {
		t.Fatalf("Load() = %#v, want %#v", got, created)
	}
}

func TestMemoryStoreInjectedFailures(t *testing.T) {
	t.Parallel()

	// Arrange
	want := errors.New("injected failure")
	store := testhelper.NewMemoryStore()
	store.SaveError = want
	store.LoadError = want

	// Act
	saveErr := store.Save(context.Background(), "key", "value")
	_, loadErr := store.Load(context.Background(), "key")

	// Assert
	if !errors.Is(saveErr, want) {
		t.Fatalf("Save() error = %v, want %v", saveErr, want)
	}
	if !errors.Is(loadErr, want) {
		t.Fatalf("Load() error = %v, want %v", loadErr, want)
	}
}

// END DOMAIN WIRING
