package problem_test

import (
	"encoding/json"
	"errors"
	"reflect"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

func TestGenericProblems(t *testing.T) {
	t.Parallel()
	entityReference := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"entityType": map[string]any{"type": "string"},
			"id":         map[string]any{"type": "string"},
		},
		"required":             []any{"entityType", "id"},
		"additionalProperties": false,
	}
	cases := []struct {
		problemType     problem.Type
		wantID          string
		wantStatus      int
		wantRecoverable bool
		wantSchema      map[string]any
	}{
		{problemType: problem.ValidationError(), wantID: "validation_error", wantStatus: 400, wantRecoverable: true, wantSchema: problem.ValidationError().DataSchema},
		{problemType: problem.EntityNotFound(), wantID: "entity_not_found", wantStatus: 404, wantRecoverable: false, wantSchema: entityReference},
		{problemType: problem.Conflict(), wantID: "conflict", wantStatus: 409, wantRecoverable: true, wantSchema: entityReference},
		{problemType: problem.Unauthenticated(), wantID: "unauthenticated", wantStatus: 401, wantRecoverable: true},
		{problemType: problem.Unauthorized(), wantID: "unauthorized", wantStatus: 403, wantRecoverable: false},
		{problemType: problem.InvalidJSON(), wantID: "invalid_json", wantStatus: 400, wantRecoverable: true},
	}
	for index, tc := range cases {
		t.Run(tc.wantID, func(t *testing.T) {
			t.Parallel()
			// Arrange
			generics := problem.GenericProblems()

			// Act
			got := generics[index]

			// Assert
			if got.ID != tc.wantID || got.Status != tc.wantStatus || got.Recoverable != tc.wantRecoverable || got.Version != "v1" || got.Title == "" {
				t.Fatalf("unexpected generic %+v", got)
			}
			if !reflect.DeepEqual(got.DataSchema, tc.wantSchema) || !reflect.DeepEqual(got, tc.problemType) {
				t.Fatalf("schema mismatch for %s: %v", got.ID, got.DataSchema)
			}
		})
	}
}

func TestValidationErrorSchemaDescribesIssues(t *testing.T) {
	t.Parallel()
	// Arrange
	want := `{"additionalProperties":false,"properties":{"issues":{"items":{"additionalProperties":false,"properties":{"code":{"type":"string"},"message":{"type":"string"},"path":{"items":{"type":"string"},"type":"array"}},"required":["path","message"],"type":"object"},"type":"array"}},"required":["issues"],"type":"object"}`

	// Act
	got, err := json.Marshal(problem.ValidationError().DataSchema)

	// Assert
	if err != nil || string(got) != want {
		t.Fatalf("schema = %s, %v", got, err)
	}
}

func TestNewRegistry(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		types   []problem.Type
		wantIDs []string
		wantDup string
	}{
		{name: "empty", wantIDs: []string{}},
		{name: "keeps order", types: []problem.Type{problem.Conflict(), problem.EntityNotFound()}, wantIDs: []string{"conflict", "entity_not_found"}},
		{name: "rejects duplicate", types: []problem.Type{problem.Conflict(), problem.Conflict()}, wantDup: "conflict"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			var duplicate *problem.DuplicateTypeError

			// Act
			registry, err := problem.NewRegistry(testPortal(), tc.types...)

			// Assert
			if tc.wantDup != "" {
				if registry != nil || !errors.As(err, &duplicate) || duplicate.ID != tc.wantDup {
					t.Fatalf("expected duplicate %s, got %v", tc.wantDup, err)
				}
				return
			}
			ids := []string{}
			for _, entry := range registry.Entries() {
				ids = append(ids, entry.ID)
			}
			if err != nil || !reflect.DeepEqual(ids, tc.wantIDs) || registry.Portal() != testPortal() {
				t.Fatalf("registry = %v, %v", ids, err)
			}
		})
	}
}

func TestRegistryLookupAndRequire(t *testing.T) {
	t.Parallel()
	cases := []struct {
		id        string
		wantFound bool
	}{
		{id: "conflict", wantFound: true},
		{id: "missing", wantFound: false},
	}
	for _, tc := range cases {
		t.Run(tc.id, func(t *testing.T) {
			t.Parallel()
			// Arrange
			registry, _ := problem.NewRegistry(testPortal(), problem.Conflict())
			var unknown *problem.UnknownTypeError

			// Act
			looked, found := registry.Lookup(tc.id)
			required, err := registry.Require(tc.id)

			// Assert
			if found != tc.wantFound || looked.ID != required.ID {
				t.Fatalf("Lookup = %+v, %t; Require = %+v", looked, found, required)
			}
			if tc.wantFound != (err == nil) || (!tc.wantFound && (!errors.As(err, &unknown) || unknown.ID != tc.id)) {
				t.Fatalf("Require error = %v", err)
			}
		})
	}
}

func TestErrorMessagesNameTheID(t *testing.T) {
	t.Parallel()
	cases := []struct {
		err  error
		want string
	}{
		{err: &problem.DuplicateTypeError{ID: "conflict"}, want: "problem type already registered: conflict"},
		{err: &problem.UnknownTypeError{ID: "missing"}, want: "no problem type registered for id: missing"},
	}
	for _, tc := range cases {
		t.Run(tc.want, func(t *testing.T) {
			t.Parallel()
			// Arrange
			err := tc.err

			// Act
			got := err.Error()

			// Assert
			if got != tc.want {
				t.Fatalf("Error = %q", got)
			}
		})
	}
}

func TestRegistryTypeURIFor(t *testing.T) {
	t.Parallel()
	// Arrange
	registry, _ := problem.NewRegistry(testPortal())

	// Act
	got, err := registry.TypeURIFor(problem.EntityNotFound())

	// Assert
	if err != nil || got != "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found" {
		t.Fatalf("TypeURIFor = %q, %v", got, err)
	}
}

func TestRegistryNewProblem(t *testing.T) {
	t.Parallel()
	noStatus := problem.Type{ID: "no_status", Title: "No Status", Version: "v1"}
	cases := []struct {
		name    string
		portal  problem.ErrorPortal
		id      string
		data    map[string]any
		want    problem.Problem
		wantErr bool
	}{
		{
			name:   "generic with data",
			portal: testPortal(),
			id:     "entity_not_found",
			data:   map[string]any{"entityType": "user", "id": "42"},
			want:   problem.Problem{Type: "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found", Title: "Entity Not Found", Status: 404, Data: map[string]any{"entityType": "user", "id": "42"}},
		},
		{
			name:   "zero status becomes 500",
			portal: testPortal(),
			id:     "no_status",
			want:   problem.Problem{Type: "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/no_status", Title: "No Status", Status: 500},
		},
		{name: "unknown id", portal: testPortal(), id: "missing", wantErr: true},
		{name: "invalid portal", portal: problem.ErrorPortal{}, id: "conflict", wantErr: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			registry, _ := problem.NewRegistry(tc.portal, problem.EntityNotFound(), problem.Conflict(), noStatus)

			// Act
			got, err := registry.NewProblem(tc.id, tc.data)

			// Assert
			if (err != nil) != tc.wantErr || !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("NewProblem = %+v, %v", got, err)
			}
		})
	}
}

func TestServiceDeclaredBusinessRuleProblem(t *testing.T) {
	t.Parallel()
	// Arrange
	schema := map[string]any{
		"type":       "object",
		"properties": map[string]any{"balance": map[string]any{"type": "integer"}},
		"required":   []any{"balance"},
	}
	insufficientFunds := problem.Type{ID: "insufficient_funds", Title: "Insufficient Funds", Version: "v1", Status: 422, Recoverable: true, DataSchema: schema}
	registry, _ := problem.NewRegistry(testPortal())
	registerErr := problem.RegisterGenerics(registry)
	declareErr := registry.Register(insufficientFunds)
	catalog := problem.NewCatalog(testPortal())
	catalogErr := catalog.AddType(insufficientFunds, problem.CatalogEndpoint{Method: "POST", Path: "/transfer"})

	// Act
	envelope, raiseErr := registry.NewProblem("insufficient_funds", map[string]any{"balance": 3})
	wire, marshalErr := json.Marshal(problem.NewError(envelope).Problem)
	var decoded map[string]any
	unmarshalErr := json.Unmarshal(wire, &decoded)
	row, _ := catalog.Lookup("insufficient_funds")

	// Assert
	if err := errors.Join(registerErr, declareErr, catalogErr, raiseErr, marshalErr, unmarshalErr); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := map[string]any{
		"type":        "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/insufficient_funds",
		"title":       "Insufficient Funds",
		"status":      float64(422),
		"recoverable": true,
		"data":        map[string]any{"balance": float64(3)},
	}
	if !reflect.DeepEqual(decoded, want) {
		t.Fatalf("wire = %v", decoded)
	}
	if !reflect.DeepEqual(row.ToCRDContent()["schema"], schema) || row.Status != 422 {
		t.Fatalf("catalog row = %v", row.ToCRDContent())
	}
}

func TestRegisterGenerics(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		preload []problem.Type
		wantErr bool
	}{
		{name: "empty registry", wantErr: false},
		{name: "already holds a generic", preload: []problem.Type{problem.Conflict()}, wantErr: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			registry, _ := problem.NewRegistry(testPortal(), tc.preload...)

			// Act
			err := problem.RegisterGenerics(registry)

			// Assert
			if (err != nil) != tc.wantErr {
				t.Fatalf("RegisterGenerics = %v", err)
			}
		})
	}
}
