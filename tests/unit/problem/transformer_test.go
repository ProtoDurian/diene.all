package problem_test

import (
	"errors"
	"fmt"
	"reflect"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

const uncataloguedLocalType = "https://local.atomi.cloud/docs/local/go/app/core/v1/uncatalogued"

func TestDefaultTransformOptions(t *testing.T) {
	t.Parallel()
	// Arrange
	want := problem.TransformOptions{Portal: problem.LocalErrorPortal(), DefaultStatus: 500, DefaultVersion: "v1"}

	// Act
	got := problem.DefaultTransformOptions()

	// Assert
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("options = %+v", got)
	}
}

func TestFromObject(t *testing.T) {
	t.Parallel()
	text := func(value string) *string { return &value }
	known := problem.Problem{Type: "t", Title: "Conflict", Status: 409}
	var typedNil *problem.Error
	registry, _ := problem.NewRegistry(testPortal(), problem.EntityNotFound(), problem.Type{ID: "no_status", Title: "No Status", Version: "v1"})
	brokenRegistry, _ := problem.NewRegistry(problem.ErrorPortal{}, problem.EntityNotFound())
	withRegistry := problem.DefaultTransformOptions()
	withRegistry.Registry = registry
	withBrokenRegistry := problem.DefaultTransformOptions()
	withBrokenRegistry.Registry = brokenRegistry
	brokenPortal := problem.DefaultTransformOptions()
	brokenPortal.Portal = problem.ErrorPortal{}
	cases := []struct {
		name    string
		value   any
		options problem.TransformOptions
		want    problem.Problem
	}{
		{name: "problem passes through", value: known, options: withRegistry, want: known},
		{name: "problem error", value: problem.NewError(known), options: withRegistry, want: known},
		{name: "wrapped problem error", value: fmt.Errorf("ctx: %w", problem.NewError(known)), options: withRegistry, want: known},
		{name: "typed-nil problem error", value: error(typedNil), options: withRegistry, want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500}},
		{
			name:    "catalogued id with data",
			value:   map[string]any{"problemId": "entity_not_found", "data": map[string]any{"entityType": "user", "id": "42"}},
			options: withRegistry,
			want:    problem.Problem{Type: "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found", Title: "Entity Not Found", Status: 404, Data: map[string]any{"entityType": "user", "id": "42"}},
		},
		{
			name:    "catalogued id without status",
			value:   map[string]any{"problemId": "no_status"},
			options: withRegistry,
			want:    problem.Problem{Type: "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/no_status", Title: "No Status", Status: 500},
		},
		{name: "catalogued id with broken portal", value: map[string]any{"problemId": "entity_not_found"}, options: withBrokenRegistry, want: problem.Problem{Type: "about:blank", Title: "Entity Not Found", Status: 404}},
		{name: "unknown id", value: map[string]any{"problemId": "missing"}, options: withRegistry, want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500, Detail: text("map[problemId:missing]")}},
		{name: "empty id", value: map[string]any{"problemId": ""}, options: withRegistry, want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500, Detail: text("map[problemId:]")}},
		{name: "map without registry", value: map[string]any{"problemId": "entity_not_found"}, options: problem.DefaultTransformOptions(), want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500, Detail: text("map[problemId:entity_not_found]")}},
		{name: "plain error", value: errors.New("disk full"), options: withRegistry, want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500, Detail: text("disk full")}},
		{name: "string", value: "boom", options: withRegistry, want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500, Detail: text("boom")}},
		{name: "other value", value: 42, options: withRegistry, want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500, Detail: text("42")}},
		{name: "nil", value: nil, options: withRegistry, want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500}},
		{name: "empty string", value: "", options: withRegistry, want: problem.Problem{Type: uncataloguedLocalType, Title: "Unexpected problem", Status: 500}},
		{name: "broken fallback portal", value: "boom", options: brokenPortal, want: problem.Problem{Type: "about:blank", Title: "Unexpected problem", Status: 500, Detail: text("boom")}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			value := tc.value

			// Act
			got := problem.FromObject(value, tc.options)

			// Assert
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("FromObject = %+v, want %+v", got, tc.want)
			}
		})
	}
}

func TestUncataloguedErrorLoop(t *testing.T) {
	t.Parallel()
	// Arrange
	options := problem.TransformOptions{Portal: testPortal(), DefaultStatus: 500, DefaultVersion: "v1"}
	quotaExceeded := problem.Type{ID: "quota_exceeded", Title: "Quota Exceeded", Version: "v1", Status: 429, Recoverable: true}
	registry, _ := problem.NewRegistry(testPortal())
	catalog := problem.NewCatalog(testPortal())

	// Act
	before := problem.FromObject(map[string]any{"problemId": "quota_exceeded"}, options)
	declareErr := errors.Join(registry.Register(quotaExceeded), catalog.AddType(quotaExceeded, problem.CatalogEndpoint{Method: "POST", Path: "/upload"}))
	options.Registry = registry
	after := problem.FromObject(map[string]any{"problemId": "quota_exceeded"}, options)
	resource, emitErr := catalog.ToResource(testIdentity())

	// Assert
	if before.Status < 500 || before.Type != "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/uncatalogued" {
		t.Fatalf("uncatalogued problem = %+v, want a plain 5xx", before)
	}
	if declareErr != nil || emitErr != nil || after.Status != 429 || !after.Recoverable {
		t.Fatalf("catalogued problem = %+v, %v, %v", after, declareErr, emitErr)
	}
	if len(resource.Spec.Problems) != 1 || resource.Spec.Problems[0]["type"] != after.Type {
		t.Fatalf("re-emitted resource = %+v", resource.Spec.Problems)
	}
}
