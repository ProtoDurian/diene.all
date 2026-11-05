// Package testhelper provides consumer-facing fakes for tests that use the sample library.
package testhelper

// DOMAIN WIRING: replaceable Note sample TestHelper.
import (
	"context"

	"github.com/ProtoDurian/diene.go-lib/lib/note"
)

// MemoryStore is an in-memory note.Store with injectable failures.
type MemoryStore struct {
	Values    map[string]string
	SaveError error
	LoadError error
}

// NewMemoryStore returns an empty MemoryStore.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{Values: map[string]string{}}
}

// Save stores value at key unless SaveError is set.
func (store *MemoryStore) Save(_ context.Context, key string, value string) error {
	if store.SaveError != nil {
		return store.SaveError
	}
	store.Values[key] = value
	return nil
}

// Load returns the value at key unless LoadError is set.
func (store *MemoryStore) Load(_ context.Context, key string) (string, error) {
	if store.LoadError != nil {
		return "", store.LoadError
	}
	return store.Values[key], nil
}

var _ note.Store = (*MemoryStore)(nil)

// END DOMAIN WIRING
