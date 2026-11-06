package note

import "strings"

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
