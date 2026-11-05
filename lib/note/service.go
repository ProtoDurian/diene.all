package note

// DOMAIN WIRING: replaceable Note sample service over the KV port.
import "context"

// Note is a stored note addressed by its slug.
type Note struct {
	Slug string
	Body string
}

// Store is the key-value port the Service persists notes through.
type Store interface {
	Save(ctx context.Context, key string, value string) error
	Load(ctx context.Context, key string) (string, error)
}

// Service creates and loads notes through a Store.
type Service struct {
	store Store
	keys  KeyComposer
}

// NewService returns a Service over store that derives keys with keys.
func NewService(store Store, keys KeyComposer) Service {
	return Service{store: store, keys: keys}
}

// Create slugs title, saves body under the slug's key and returns the stored note.
func (service Service) Create(ctx context.Context, title string, body string) (Note, error) {
	value := Note{Slug: service.keys.Slug(title), Body: body}
	if err := service.store.Save(ctx, service.keys.Compose(value.Slug), value.Body); err != nil {
		return Note{}, err
	}
	return value, nil
}

// Load returns the note stored under slug.
func (service Service) Load(ctx context.Context, slug string) (Note, error) {
	body, err := service.store.Load(ctx, service.keys.Compose(slug))
	if err != nil {
		return Note{}, err
	}
	return Note{Slug: slug, Body: body}, nil
}

// END DOMAIN WIRING
