package ledger

import (
	"context"
	"fmt"
)

type Coordinate struct {
	Platform  string `json:"platform"`
	Landscape string `json:"landscape"`
	Class     string `json:"class"`
	Module    string `json:"module"`
}

func (c Coordinate) Key() string {
	return c.Platform + "/" + c.Landscape + "/" + c.Class + "/" + c.Module
}

type Phase string

const (
	PhaseIntent    Phase = "intent"
	PhaseCreated   Phase = "created"
	PhaseConfirmed Phase = "confirmed"
	PhaseOrphaned  Phase = "orphaned"
)

type Entry struct {
	Coordinate Coordinate `json:"coordinate"`
	Phase      Phase      `json:"phase"`
	ExternalID string     `json:"externalId"`
	SecretPath string     `json:"secretPath"`
}

// Store has no Delete: a CR delete orphans the entry, never destroys it.
type Store interface {
	Get(ctx context.Context, key string) (Entry, bool, error)
	Put(ctx context.Context, entry Entry) error
}

type Service struct {
	store Store
}

func NewService(store Store) Service {
	return Service{store: store}
}

func (s Service) Get(ctx context.Context, coord Coordinate) (Entry, bool, error) {
	return s.store.Get(ctx, coord.Key())
}

func (s Service) Intent(ctx context.Context, coord Coordinate, externalID, secretPath string) (Entry, error) {
	existing, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, err
	}
	if ok {
		return existing, nil
	}
	entry := Entry{Coordinate: coord, Phase: PhaseIntent, ExternalID: externalID, SecretPath: secretPath}
	if err := s.store.Put(ctx, entry); err != nil {
		return Entry{}, err
	}
	return entry, nil
}

func (s Service) Adopt(ctx context.Context, coord Coordinate) (Entry, error) {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, err
	}
	if !ok {
		return Entry{}, fmt.Errorf("ledger: cannot adopt missing entry %s", coord.Key())
	}
	if entry.Phase == PhaseOrphaned {
		entry.Phase = PhaseCreated
		if err := s.store.Put(ctx, entry); err != nil {
			return Entry{}, err
		}
	}
	return entry, nil
}

func (s Service) Created(ctx context.Context, coord Coordinate) (Entry, error) {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, err
	}
	if !ok {
		return Entry{}, fmt.Errorf("ledger: cannot mark created missing entry %s", coord.Key())
	}
	if entry.Phase == PhaseIntent {
		entry.Phase = PhaseCreated
		if err := s.store.Put(ctx, entry); err != nil {
			return Entry{}, err
		}
	}
	return entry, nil
}

func (s Service) Confirm(ctx context.Context, coord Coordinate) (Entry, error) {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return Entry{}, err
	}
	if !ok {
		return Entry{}, fmt.Errorf("ledger: cannot confirm missing entry %s", coord.Key())
	}
	// Only created advances; an orphaned entry is never confirmed.
	if entry.Phase == PhaseCreated {
		entry.Phase = PhaseConfirmed
		if err := s.store.Put(ctx, entry); err != nil {
			return Entry{}, err
		}
	}
	return entry, nil
}

func (s Service) Orphan(ctx context.Context, coord Coordinate) error {
	entry, ok, err := s.store.Get(ctx, coord.Key())
	if err != nil {
		return err
	}
	if !ok {
		return nil
	}
	entry.Phase = PhaseOrphaned
	return s.store.Put(ctx, entry)
}
