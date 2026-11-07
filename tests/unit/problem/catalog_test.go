package problem_test

import (
	"fmt"
	"reflect"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

func TestCatalogEndpointToContent(t *testing.T) {
	t.Parallel()
	// Arrange
	endpoint := problem.CatalogEndpoint{Method: "POST", Path: "/user"}

	// Act
	content := endpoint.ToContent()

	// Assert
	if !reflect.DeepEqual(content, map[string]any{"method": "POST", "path": "/user"}) {
		t.Fatalf("content = %v", content)
	}
}

func TestCatalogEntryToCRDContent(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name  string
		entry problem.CatalogEntry
		want  map[string]any
	}{
		{
			name:  "with schema and endpoints",
			entry: problem.CatalogEntry{ID: "conflict", TypeURI: "u", Title: "Conflict", Status: 409, Recoverable: true, DataSchema: map[string]any{"type": "object"}, Endpoints: []problem.CatalogEndpoint{{Method: "POST", Path: "/user"}}},
			want: map[string]any{
				"id": "conflict", "type": "u", "title": "Conflict", "status": 409, "recoverable": true,
				"schema": map[string]any{"type": "object"}, "endpoints": []map[string]any{{"method": "POST", "path": "/user"}},
			},
		},
		{
			name:  "no data renders not-anything schema",
			entry: problem.CatalogEntry{ID: "unauthorized", TypeURI: "u", Title: "Unauthorized", Status: 403},
			want: map[string]any{
				"id": "unauthorized", "type": "u", "title": "Unauthorized", "status": 403, "recoverable": false,
				"schema": map[string]any{"not": map[string]any{}}, "endpoints": []map[string]any{},
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			entry := tc.entry

			// Act
			got := entry.ToCRDContent()

			// Assert
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("content = %v", got)
			}
		})
	}
}

func TestNewCatalogHoldsEntriesAndPortal(t *testing.T) {
	t.Parallel()
	// Arrange
	entry := problem.CatalogEntry{ID: "x", TypeURI: "t", Title: "X", Status: 500}

	// Act
	catalog := problem.NewCatalog(testPortal(), entry)

	// Assert
	if !reflect.DeepEqual(catalog.Entries(), []problem.CatalogEntry{entry}) || catalog.Portal() != testPortal() {
		t.Fatalf("catalog = %v", catalog.Entries())
	}
}

func TestCatalogAddReplacesInPlace(t *testing.T) {
	t.Parallel()
	// Arrange
	catalog := problem.NewCatalog(testPortal())

	// Act
	catalog.Add(problem.CatalogEntry{ID: "a", Title: "first"})
	catalog.Add(problem.CatalogEntry{ID: "b", Title: "second"})
	catalog.Add(problem.CatalogEntry{ID: "a", Title: "replaced"})

	// Assert
	entries := catalog.Entries()
	if len(entries) != 2 || entries[0].Title != "replaced" || entries[1].ID != "b" {
		t.Fatalf("entries = %+v", entries)
	}
}

func TestCatalogAddType(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name        string
		portal      problem.ErrorPortal
		problemType problem.Type
		endpoints   []problem.CatalogEndpoint
		want        problem.CatalogEntry
		wantErr     bool
	}{
		{
			name:        "generic with endpoint",
			portal:      testPortal(),
			problemType: problem.EntityNotFound(),
			endpoints:   []problem.CatalogEndpoint{{Method: "GET", Path: "/user/{id}"}},
			want: problem.CatalogEntry{
				ID: "entity_not_found", TypeURI: "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found",
				Title: "Entity Not Found", Status: 404, DataSchema: problem.EntityNotFound().DataSchema,
				Endpoints: []problem.CatalogEndpoint{{Method: "GET", Path: "/user/{id}"}},
			},
		},
		{
			name:        "zero status becomes 500",
			portal:      testPortal(),
			problemType: problem.Type{ID: "custom", Title: "Custom", Version: "v1"},
			want: problem.CatalogEntry{
				ID: "custom", TypeURI: "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/custom",
				Title: "Custom", Status: 500, Endpoints: []problem.CatalogEndpoint{},
			},
		},
		{name: "invalid portal", portal: problem.ErrorPortal{}, problemType: problem.Conflict(), wantErr: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			catalog := problem.NewCatalog(tc.portal)

			// Act
			err := catalog.AddType(tc.problemType, tc.endpoints...)
			got, found := catalog.Lookup(tc.problemType.ID)

			// Assert
			if (err != nil) != tc.wantErr || found == tc.wantErr || !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("AddType = %v; entry = %+v", err, got)
			}
		})
	}
}

func TestCatalogAddGenerics(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name     string
		portal   problem.ErrorPortal
		wantRows []string
		wantErr  bool
	}{
		{name: "valid portal", portal: testPortal(), wantRows: []string{"validation_error", "entity_not_found", "conflict", "unauthenticated", "unauthorized", "invalid_json"}},
		{name: "invalid portal", portal: problem.ErrorPortal{}, wantRows: []string{}, wantErr: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			catalog := problem.NewCatalog(tc.portal)

			// Act
			err := catalog.AddGenerics()
			content := catalog.ToCRDContent()

			// Assert
			rows := []string{}
			for _, row := range content {
				rows = append(rows, fmt.Sprint(row["id"]))
			}
			if (err != nil) != tc.wantErr || !reflect.DeepEqual(rows, tc.wantRows) {
				t.Fatalf("AddGenerics = %v; rows = %v", err, rows)
			}
		})
	}
}
