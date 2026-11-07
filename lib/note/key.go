// Package note is the replaceable sample library: slugged notes stored behind a key-value port.
package note

// DOMAIN WIRING: replaceable Note sample key composition.
import "strings"

// KeyComposer turns note titles into slugs and slugs into namespaced storage keys.
type KeyComposer struct {
	namespace string
}

// NewKeyComposer returns a KeyComposer that prefixes keys with namespace.
func NewKeyComposer(namespace string) KeyComposer {
	return KeyComposer{namespace: namespace}
}

// Slug lower-cases value and joins its words with hyphens.
func (KeyComposer) Slug(value string) string {
	return strings.Join(strings.Fields(strings.ToLower(value)), "-")
}

// Compose returns the storage key for key inside the composer's namespace.
func (keys KeyComposer) Compose(key string) string {
	return keys.namespace + ":" + key
}

// END DOMAIN WIRING
