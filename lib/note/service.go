package note

import "context"

type Note struct {
	Slug string
	Body string
}

type Store interface {
	Save(ctx context.Context, key string, value string) error
	Load(ctx context.Context, key string) (string, error)
}

type Service struct {
	store Store
	keys  KeyComposer
}

func NewService(store Store, keys KeyComposer) Service {
	return Service{store: store, keys: keys}
}

func (service Service) Create(ctx context.Context, title string, body string) (Note, error) {
	value := Note{Slug: service.keys.Slug(title), Body: body}
	if err := service.store.Save(ctx, service.keys.Compose(value.Slug), value.Body); err != nil {
		return Note{}, err
	}
	return value, nil
}

func (service Service) Load(ctx context.Context, slug string) (Note, error) {
	body, err := service.store.Load(ctx, service.keys.Compose(slug))
	if err != nil {
		return Note{}, err
	}
	return Note{Slug: slug, Body: body}, nil
}
