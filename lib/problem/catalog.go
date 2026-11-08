package problem

// CatalogEndpoint is a method and path that can return a problem.
type CatalogEndpoint struct {
	Method string
	Path   string
}

// ToContent renders the endpoint as its Problem resource member.
func (e CatalogEndpoint) ToContent() map[string]any {
	return map[string]any{
		"method": e.Method,
		"path":   e.Path,
	}
}

// CatalogEntry is one catalogued problem; TypeURI must come from [TypeURI].
type CatalogEntry struct {
	ID          string
	TypeURI     string
	Title       string
	Status      int
	Recoverable bool
	DataSchema  map[string]any
	Endpoints   []CatalogEndpoint
}

// ToCRDContent renders `{id, type, title, status, recoverable, schema, endpoints[]}`; no data schema renders `{"not":{}}`.
func (e CatalogEntry) ToCRDContent() map[string]any {
	endpoints := make([]map[string]any, 0, len(e.Endpoints))
	for _, endpoint := range e.Endpoints {
		endpoints = append(endpoints, endpoint.ToContent())
	}
	schema := e.DataSchema
	if schema == nil {
		schema = map[string]any{"not": map[string]any{}}
	}
	return map[string]any{
		"id":          e.ID,
		"type":        e.TypeURI,
		"title":       e.Title,
		"status":      e.Status,
		"recoverable": e.Recoverable,
		"schema":      schema,
		"endpoints":   endpoints,
	}
}

// Catalog is the ordered set of entries one service row publishes.
type Catalog struct {
	portal  ErrorPortal
	entries map[string]CatalogEntry
	order   []string
}

// NewCatalog creates a catalog bound to portal holding entries.
func NewCatalog(portal ErrorPortal, entries ...CatalogEntry) *Catalog {
	catalog := &Catalog{portal: portal, entries: make(map[string]CatalogEntry, len(entries))}
	for _, entry := range entries {
		catalog.Add(entry)
	}
	return catalog
}

// Portal returns the portal the catalog builds type URIs from.
func (c *Catalog) Portal() ErrorPortal {
	return c.portal
}

// Add stores entry, replacing an entry with the same id in place.
func (c *Catalog) Add(entry CatalogEntry) {
	if _, exists := c.entries[entry.ID]; !exists {
		c.order = append(c.order, entry.ID)
	}
	c.entries[entry.ID] = entry
}

// AddType adds an entry for problemType with endpoints; a zero status becomes 500.
func (c *Catalog) AddType(problemType Type, endpoints ...CatalogEndpoint) error {
	typeURI, err := TypeURI(c.portal, problemType.Version, problemType.ID)
	if err != nil {
		return err
	}
	status := problemType.Status
	if status == 0 {
		status = defaultProblemStatus
	}
	if endpoints == nil {
		endpoints = []CatalogEndpoint{}
	}
	c.Add(CatalogEntry{
		ID:          problemType.ID,
		TypeURI:     typeURI,
		Title:       problemType.Title,
		Status:      status,
		Recoverable: problemType.Recoverable,
		DataSchema:  problemType.DataSchema,
		Endpoints:   endpoints,
	})
	return nil
}

// AddGenerics adds every [GenericProblems] entry.
func (c *Catalog) AddGenerics() error {
	for _, problemType := range GenericProblems() {
		if err := c.AddType(problemType); err != nil {
			return err
		}
	}
	return nil
}

// Lookup returns the entry for id and whether it was present.
func (c *Catalog) Lookup(id string) (CatalogEntry, bool) {
	entry, ok := c.entries[id]
	return entry, ok
}

// Entries returns the entries in insertion order.
func (c *Catalog) Entries() []CatalogEntry {
	entries := make([]CatalogEntry, 0, len(c.order))
	for _, id := range c.order {
		entries = append(entries, c.entries[id])
	}
	return entries
}

// ToCRDContent renders every entry as the Problem resource `problems[]` list.
func (c *Catalog) ToCRDContent() []map[string]any {
	content := make([]map[string]any, 0, len(c.order))
	for _, id := range c.order {
		content = append(content, c.entries[id].ToCRDContent())
	}
	return content
}
