package problem_test

import (
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

type wireSpec struct {
	problem.ResourceIdentity

	Problems []wireProblemRow `json:"problems"`
}

type wireResource struct {
	APIVersion string                   `json:"apiVersion"`
	Kind       string                   `json:"kind"`
	Metadata   problem.ResourceMetadata `json:"metadata"`
	Spec       wireSpec                 `json:"spec"`
}

func testIdentity() problem.ResourceIdentity {
	return problem.ResourceIdentity{Platform: "go", Service: "user", Module: "api", Landscape: "raichu", Version: "v1"}
}

func TestCatalogToResourceRoundTripsEveryField(t *testing.T) {
	t.Parallel()
	// Arrange
	catalog := problem.NewCatalog(testPortal())
	addErr := errors.Join(
		catalog.AddGenerics(),
		catalog.AddType(problem.EntityNotFound(), problem.CatalogEndpoint{Method: "GET", Path: "/user/{id}"}, problem.CatalogEndpoint{Method: "DELETE", Path: "/user/{id}"}),
	)

	// Act
	resource, err := catalog.ToResource(testIdentity())
	manifest, marshalErr := json.Marshal(resource)
	var decoded wireResource
	unmarshalErr := json.Unmarshal(manifest, &decoded)

	// Assert
	if joined := errors.Join(addErr, err, marshalErr, unmarshalErr); joined != nil {
		t.Fatalf("unexpected error: %v", joined)
	}
	if decoded.APIVersion != "atomi.cloud/v1alpha1" || decoded.Kind != "Problem" ||
		decoded.Metadata.Name != "user.api.raichu.v1" || decoded.Metadata.Namespace != "go" ||
		decoded.Spec.ResourceIdentity != testIdentity() {
		t.Fatalf("resource header = %+v", decoded)
	}
	entries := catalog.Entries()
	if len(decoded.Spec.Problems) != len(entries) {
		t.Fatalf("problems = %d, want %d", len(decoded.Spec.Problems), len(entries))
	}
	for index, entry := range entries {
		row := decoded.Spec.Problems[index]
		wantSchema := entry.DataSchema
		if wantSchema == nil {
			wantSchema = map[string]any{"not": map[string]any{}}
		}
		roundTrippedSchema, _ := json.Marshal(row.Schema)
		expectedSchema, _ := json.Marshal(wantSchema)
		endpoints := make([]problem.CatalogEndpoint, 0, len(row.Endpoints))
		for _, endpoint := range row.Endpoints {
			endpoints = append(endpoints, problem.CatalogEndpoint{Method: endpoint.Method, Path: endpoint.Path})
		}
		if row.ID != entry.ID || row.Type != entry.TypeURI || row.Title != entry.Title || row.Status != entry.Status ||
			row.Recoverable != entry.Recoverable || string(roundTrippedSchema) != string(expectedSchema) ||
			!reflect.DeepEqual(endpoints, entry.Endpoints) {
			t.Fatalf("row %d = %+v, want %+v", index, row, entry)
		}
	}
}

func TestCatalogToResourceRefuses(t *testing.T) {
	t.Parallel()
	long := strings.Repeat("a", 64)
	withIdentity := func(change func(*problem.ResourceIdentity)) problem.ResourceIdentity {
		identity := testIdentity()
		change(&identity)
		return identity
	}
	httpPortal := testPortal()
	httpPortal.Scheme = "http"
	cases := []struct {
		name      string
		portal    problem.ErrorPortal
		identity  problem.ResourceIdentity
		entries   []problem.CatalogEntry
		types     []problem.Type
		wantField string
	}{
		{name: "non-https portal", portal: httpPortal, identity: testIdentity(), wantField: "scheme"},
		{name: "platform not a label", portal: testPortal(), identity: withIdentity(func(i *problem.ResourceIdentity) { i.Platform = "Go" }), wantField: "platform"},
		{name: "service too long", portal: testPortal(), identity: withIdentity(func(i *problem.ResourceIdentity) { i.Service = long }), wantField: "service"},
		{name: "module with dot", portal: testPortal(), identity: withIdentity(func(i *problem.ResourceIdentity) { i.Module = "a.b" }), wantField: "module"},
		{name: "landscape trailing dash", portal: testPortal(), identity: withIdentity(func(i *problem.ResourceIdentity) { i.Landscape = "raichu-" }), wantField: "landscape"},
		{name: "service not the portal's", portal: testPortal(), identity: withIdentity(func(i *problem.ResourceIdentity) { i.Service = "billing" }), wantField: "service"},
		{name: "version without v", portal: testPortal(), identity: withIdentity(func(i *problem.ResourceIdentity) { i.Version = "1" }), wantField: "version"},
		{name: "version zero", portal: testPortal(), identity: withIdentity(func(i *problem.ResourceIdentity) { i.Version = "v0" }), wantField: "version"},
		{name: "name too long", portal: testPortal(), identity: withIdentity(func(i *problem.ResourceIdentity) { i.Version = "v1" + strings.Repeat("0", 240) }), wantField: "name"},
		{name: "hand-written type URI", portal: testPortal(), identity: testIdentity(), entries: []problem.CatalogEntry{{ID: "conflict", TypeURI: "https://elsewhere/conflict", Status: 409}}, wantField: "type"},
		{name: "entry id not a segment", portal: testPortal(), identity: testIdentity(), entries: []problem.CatalogEntry{{ID: "a/b", TypeURI: "x"}}, wantField: "type"},
		{name: "entry at another version", portal: testPortal(), identity: testIdentity(), types: []problem.Type{{ID: "later", Title: "Later", Version: "v2", Status: 409}}, wantField: "type"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			catalog := problem.NewCatalog(tc.portal, tc.entries...)
			for _, problemType := range tc.types {
				if err := catalog.AddType(problemType); err != nil {
					t.Fatalf("AddType: %v", err)
				}
			}
			var invalid *problem.InvalidResourceError

			// Act
			resource, err := catalog.ToResource(tc.identity)

			// Assert
			if !errors.As(err, &invalid) || invalid.Field != tc.wantField || !reflect.DeepEqual(resource, problem.Resource{}) {
				t.Fatalf("ToResource = %+v, %v; want %s refusal", resource, err, tc.wantField)
			}
		})
	}
}

func TestInvalidResourceErrorMessage(t *testing.T) {
	t.Parallel()
	// Arrange
	err := &problem.InvalidResourceError{Field: "version", Value: "1", Reason: "must look like v1"}

	// Act
	message := err.Error()

	// Assert
	if message != `problem resource version must look like v1, got "1"` {
		t.Fatalf("message = %q", message)
	}
}
