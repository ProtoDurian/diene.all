package problem

// Type is a versioned problem declaration; a new Version mints a new type URI.
type Type struct {
	ID          string
	Title       string
	Version     string
	Status      int
	Recoverable bool
	DataSchema  map[string]any
}

// DuplicateTypeError reports a problem id registered twice.
type DuplicateTypeError struct {
	ID string
}

// Error implements the error interface.
func (e *DuplicateTypeError) Error() string {
	return "problem type already registered: " + e.ID
}

// UnknownTypeError reports a lookup for an unregistered problem id.
type UnknownTypeError struct {
	ID string
}

// Error implements the error interface.
func (e *UnknownTypeError) Error() string {
	return "no problem type registered for id: " + e.ID
}

// Registry is an ordered set of problem types bound to one portal.
type Registry struct {
	portal ErrorPortal
	types  map[string]Type
	order  []string
}

// NewRegistry creates a registry bound to portal holding types.
func NewRegistry(portal ErrorPortal, types ...Type) (*Registry, error) {
	registry := &Registry{portal: portal, types: make(map[string]Type, len(types))}
	for _, problemType := range types {
		if err := registry.Register(problemType); err != nil {
			return nil, err
		}
	}
	return registry, nil
}

// Portal returns the portal every type URI is built from.
func (r *Registry) Portal() ErrorPortal {
	return r.portal
}

// Register adds problemType, rejecting a duplicate id.
func (r *Registry) Register(problemType Type) error {
	if _, exists := r.types[problemType.ID]; exists {
		return &DuplicateTypeError{ID: problemType.ID}
	}
	r.types[problemType.ID] = problemType
	r.order = append(r.order, problemType.ID)
	return nil
}

// Lookup returns the type registered for id and whether it was present.
func (r *Registry) Lookup(id string) (Type, bool) {
	problemType, ok := r.types[id]
	return problemType, ok
}

// Require returns the type registered for id, or an [UnknownTypeError].
func (r *Registry) Require(id string) (Type, error) {
	problemType, ok := r.types[id]
	if !ok {
		return Type{}, &UnknownTypeError{ID: id}
	}
	return problemType, nil
}

// Entries returns the registered types in insertion order.
func (r *Registry) Entries() []Type {
	entries := make([]Type, 0, len(r.order))
	for _, id := range r.order {
		entries = append(entries, r.types[id])
	}
	return entries
}

// TypeURIFor builds the type URI for problemType from the registry's portal.
func (r *Registry) TypeURIFor(problemType Type) (string, error) {
	return TypeURI(r.portal, problemType.Version, problemType.ID)
}

// NewProblem builds the envelope for the registered id carrying data.
func (r *Registry) NewProblem(id string, data map[string]any) (Problem, error) {
	problemType, err := r.Require(id)
	if err != nil {
		return Problem{}, err
	}
	typeURI, err := r.TypeURIFor(problemType)
	if err != nil {
		return Problem{}, err
	}
	status := problemType.Status
	if status == 0 {
		status = defaultProblemStatus
	}
	return Problem{
		Type:        typeURI,
		Title:       problemType.Title,
		Status:      status,
		Recoverable: problemType.Recoverable,
		Data:        data,
	}, nil
}

func entityReferenceSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"entityType": map[string]any{"type": "string"},
			"id":         map[string]any{"type": "string"},
		},
		"required":             []any{"entityType", "id"},
		"additionalProperties": false,
	}
}

// ValidationError is the generic 400 problem for a request that failed validation.
func ValidationError() Type {
	return Type{
		ID:          "validation_error",
		Title:       "Validation Error",
		Version:     defaultProblemVersion,
		Status:      400,
		Recoverable: true,
		DataSchema: map[string]any{
			"type": "object",
			"properties": map[string]any{
				"issues": map[string]any{
					"type": "array",
					"items": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"path":    map[string]any{"type": "array", "items": map[string]any{"type": "string"}},
							"message": map[string]any{"type": "string"},
							"code":    map[string]any{"type": "string"},
						},
						"required":             []any{"path", "message"},
						"additionalProperties": false,
					},
				},
			},
			"required":             []any{"issues"},
			"additionalProperties": false,
		},
	}
}

// EntityNotFound is the generic 404 problem for a missing entity.
func EntityNotFound() Type {
	return Type{
		ID:          "entity_not_found",
		Title:       "Entity Not Found",
		Version:     defaultProblemVersion,
		Status:      404,
		Recoverable: false,
		DataSchema:  entityReferenceSchema(),
	}
}

// Conflict is the generic 409 problem for a state conflict on an entity.
func Conflict() Type {
	return Type{
		ID:          "conflict",
		Title:       "Conflict",
		Version:     defaultProblemVersion,
		Status:      409,
		Recoverable: true,
		DataSchema:  entityReferenceSchema(),
	}
}

// Unauthenticated is the generic 401 problem for a missing or invalid identity.
func Unauthenticated() Type {
	return Type{
		ID:          "unauthenticated",
		Title:       "Unauthenticated",
		Version:     defaultProblemVersion,
		Status:      401,
		Recoverable: true,
	}
}

// Unauthorized is the generic 403 problem for an identity without permission.
func Unauthorized() Type {
	return Type{
		ID:          "unauthorized",
		Title:       "Unauthorized",
		Version:     defaultProblemVersion,
		Status:      403,
		Recoverable: false,
	}
}

// InvalidJSON is the generic 400 problem for a body that is not valid JSON.
func InvalidJSON() Type {
	return Type{
		ID:          "invalid_json",
		Title:       "Invalid JSON",
		Version:     defaultProblemVersion,
		Status:      400,
		Recoverable: true,
	}
}

// GenericProblems returns the portable v1 baseline in stable order.
func GenericProblems() []Type {
	return []Type{
		ValidationError(),
		EntityNotFound(),
		Conflict(),
		Unauthenticated(),
		Unauthorized(),
		InvalidJSON(),
	}
}

// RegisterGenerics registers [GenericProblems] on registry.
func RegisterGenerics(registry *Registry) error {
	for _, problemType := range GenericProblems() {
		if err := registry.Register(problemType); err != nil {
			return err
		}
	}
	return nil
}
