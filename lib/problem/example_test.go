package problem_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

func examplePortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.raichu.cluster.atomi.cloud",
		Landscape: "raichu",
		Platform:  "go",
		Service:   "user",
		Module:    "api",
	}
}

func exampleIdentity() problem.ResourceIdentity {
	return problem.ResourceIdentity{Platform: "go", Service: "user", Module: "api", Landscape: "raichu", Version: "v1"}
}

func ExampleTypeURI() {
	// Arrange
	portal := examplePortal()

	// Act
	uri, _ := problem.TypeURI(portal, "v1", "entity_not_found")

	// Assert
	fmt.Println(uri)
	// Output: https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found
}

func ExampleErrorPortal() {
	// Arrange
	portal := problem.ErrorPortal{Scheme: "https", Host: "docs.example", Landscape: "lapras", Platform: "zinc", Service: "user", Module: "api"}

	// Act
	uri, _ := problem.TypeURI(portal, "v2", "conflict")

	// Assert
	fmt.Println(uri)
	// Output: https://docs.example/docs/lapras/zinc/user/api/v2/conflict
}

func ExampleLocalErrorPortal() {
	// Arrange
	portal := problem.LocalErrorPortal()

	// Act
	uri, _ := problem.TypeURI(portal, "v1", "local_error")

	// Assert
	fmt.Println(uri)
	// Output: https://local.atomi.cloud/docs/local/go/app/core/v1/local_error
}

func ExampleInvalidSegmentError() {
	// Arrange
	var segmentErr *problem.InvalidSegmentError

	// Act
	_, err := problem.TypeURI(problem.LocalErrorPortal(), "v1", "bad/id")

	// Assert
	fmt.Println(errors.As(err, &segmentErr), segmentErr.Name)
	// Output: true id
}

func ExampleProblem() {
	// Arrange
	withData := problem.Problem{Type: "https://docs.example/v1/entity_not_found", Title: "Entity Not Found", Status: 404, Data: map[string]any{"entityType": "user", "id": "42"}}
	withoutData := problem.Problem{Type: "https://docs.example/v1/unauthorized", Title: "Unauthorized", Status: 403}

	// Act
	first, _ := json.Marshal(withData)
	second, _ := json.Marshal(withoutData)
	var decoded problem.Problem
	_ = json.Unmarshal(first, &decoded)

	// Assert
	fmt.Println(string(first))
	fmt.Println(string(second))
	fmt.Println(decoded.Equal(withData), decoded.String())
	// Output:
	// {"data":{"entityType":"user","id":"42"},"recoverable":false,"status":404,"title":"Entity Not Found","type":"https://docs.example/v1/entity_not_found"}
	// {"recoverable":false,"status":403,"title":"Unauthorized","type":"https://docs.example/v1/unauthorized"}
	// true Problem(https://docs.example/v1/entity_not_found, 404, Entity Not Found)
}

func ExampleError() {
	// Arrange
	envelope := problem.Problem{Type: "https://x/v1/conflict", Title: "Conflict", Status: 409}
	var problemErr *problem.Error

	// Act
	err := fmt.Errorf("saving user: %w", problem.NewError(envelope))

	// Assert
	fmt.Println(errors.As(err, &problemErr), problemErr.Problem.Status)
	// Output: true 409
}

func ExampleNewError() {
	// Arrange
	envelope := problem.Problem{Type: "https://x/v1/unauthorized", Title: "Unauthorized", Status: 403}

	// Act
	err := problem.NewError(envelope)

	// Assert
	fmt.Println(err)
	// Output: Problem(https://x/v1/unauthorized, 403, Unauthorized)
}

func ExampleWrapError() {
	// Arrange
	cause := errors.New("connection reset")
	envelope := problem.Problem{Type: "https://x/v1/conflict", Title: "Conflict", Status: 409}

	// Act
	err := problem.WrapError(envelope, cause)

	// Assert
	fmt.Println(err, errors.Is(err, cause), errors.Is(err.Unwrap(), cause))
	// Output: Problem(https://x/v1/conflict, 409, Conflict): connection reset true true
}

func ExampleType() {
	// Arrange
	problemType := problem.Type{ID: "quota_exceeded", Title: "Quota Exceeded", Version: "v1", Status: 429, Recoverable: true}

	// Act
	uri, _ := problem.TypeURI(examplePortal(), problemType.Version, problemType.ID)

	// Assert
	fmt.Println(problemType.Title, problemType.Status, problemType.Recoverable, uri)
	// Output: Quota Exceeded 429 true https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/quota_exceeded
}

func ExampleDuplicateTypeError() {
	// Arrange
	var duplicate *problem.DuplicateTypeError

	// Act
	_, err := problem.NewRegistry(examplePortal(), problem.Conflict(), problem.Conflict())

	// Assert
	fmt.Println(errors.As(err, &duplicate), err)
	// Output: true problem type already registered: conflict
}

func ExampleUnknownTypeError() {
	// Arrange
	registry, _ := problem.NewRegistry(examplePortal())
	var unknown *problem.UnknownTypeError

	// Act
	_, err := registry.Require("missing")

	// Assert
	fmt.Println(errors.As(err, &unknown), err)
	// Output: true no problem type registered for id: missing
}

func ExampleRegistry() {
	// Arrange
	registry, _ := problem.NewRegistry(examplePortal())
	_ = problem.RegisterGenerics(registry)

	// Act
	entityNotFound, _ := registry.Require("entity_not_found")
	_, found := registry.Lookup("conflict")
	uri, _ := registry.TypeURIFor(entityNotFound)

	// Assert
	fmt.Println(len(registry.Entries()), found, registry.Portal().Service)
	fmt.Println(uri)
	// Output:
	// 6 true user
	// https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found
}

func ExampleNewRegistry() {
	// Arrange
	types := problem.GenericProblems()

	// Act
	registry, err := problem.NewRegistry(examplePortal(), types...)

	// Assert
	fmt.Println(err, len(registry.Entries()))
	// Output: <nil> 6
}

// A business rule is a problem the service declares itself, with its own id, status, flag and schema.
func ExampleRegistry_NewProblem() {
	// Arrange
	insufficientFunds := problem.Type{
		ID:          "insufficient_funds",
		Title:       "Insufficient Funds",
		Version:     "v1",
		Status:      422,
		Recoverable: true,
		DataSchema: map[string]any{
			"type":       "object",
			"properties": map[string]any{"balance": map[string]any{"type": "integer"}},
			"required":   []any{"balance"},
		},
	}
	registry, _ := problem.NewRegistry(examplePortal(), insufficientFunds)

	// Act
	envelope, _ := registry.NewProblem("insufficient_funds", map[string]any{"balance": 3})
	wire, _ := json.Marshal(envelope)

	// Assert
	fmt.Println(string(wire))
	// Output: {"data":{"balance":3},"recoverable":true,"status":422,"title":"Insufficient Funds","type":"https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/insufficient_funds"}
}

func ExampleValidationError() {
	// Arrange
	problemType := problem.ValidationError()

	// Act
	_, hasSchema := problemType.DataSchema["properties"].(map[string]any)["issues"]

	// Assert
	fmt.Println(problemType.ID, problemType.Status, problemType.Recoverable, hasSchema)
	// Output: validation_error 400 true true
}

func ExampleEntityNotFound() {
	// Arrange
	problemType := problem.EntityNotFound()

	// Act
	required := problemType.DataSchema["required"]

	// Assert
	fmt.Println(problemType.ID, problemType.Status, problemType.Recoverable, required)
	// Output: entity_not_found 404 false [entityType id]
}

func ExampleConflict() {
	// Arrange
	problemType := problem.Conflict()

	// Act
	required := problemType.DataSchema["required"]

	// Assert
	fmt.Println(problemType.ID, problemType.Status, problemType.Recoverable, required)
	// Output: conflict 409 true [entityType id]
}

func ExampleUnauthenticated() {
	// Arrange
	problemType := problem.Unauthenticated()

	// Act
	hasData := problemType.DataSchema != nil

	// Assert
	fmt.Println(problemType.ID, problemType.Status, problemType.Recoverable, hasData)
	// Output: unauthenticated 401 true false
}

func ExampleUnauthorized() {
	// Arrange
	problemType := problem.Unauthorized()

	// Act
	hasData := problemType.DataSchema != nil

	// Assert
	fmt.Println(problemType.ID, problemType.Status, problemType.Recoverable, hasData)
	// Output: unauthorized 403 false false
}

func ExampleInvalidJSON() {
	// Arrange
	problemType := problem.InvalidJSON()

	// Act
	hasData := problemType.DataSchema != nil

	// Assert
	fmt.Println(problemType.ID, problemType.Status, problemType.Recoverable, hasData)
	// Output: invalid_json 400 true false
}

func ExampleGenericProblems() {
	// Arrange
	generics := problem.GenericProblems()

	// Act
	ids := make([]string, 0, len(generics))
	for _, problemType := range generics {
		ids = append(ids, problemType.ID)
	}

	// Assert
	fmt.Println(ids)
	// Output: [validation_error entity_not_found conflict unauthenticated unauthorized invalid_json]
}

func ExampleRegisterGenerics() {
	// Arrange
	registry, _ := problem.NewRegistry(examplePortal())

	// Act
	err := problem.RegisterGenerics(registry)

	// Assert
	fmt.Println(err, len(registry.Entries()))
	// Output: <nil> 6
}

func ExampleCatalogEndpoint() {
	// Arrange
	endpoint := problem.CatalogEndpoint{Method: "GET", Path: "/user/{id}"}

	// Act
	content := endpoint.ToContent()

	// Assert
	fmt.Println(content)
	// Output: map[method:GET path:/user/{id}]
}

func ExampleCatalogEntry() {
	// Arrange
	uri, _ := problem.TypeURI(examplePortal(), "v1", "unauthorized")
	entry := problem.CatalogEntry{ID: "unauthorized", TypeURI: uri, Title: "Unauthorized", Status: 403}

	// Act
	content := entry.ToCRDContent()

	// Assert
	fmt.Println(content["schema"], content["endpoints"])
	// Output: map[not:map[]] []
}

func ExampleCatalog() {
	// Arrange
	catalog := problem.NewCatalog(examplePortal())

	// Act
	_ = catalog.AddType(problem.EntityNotFound(), problem.CatalogEndpoint{Method: "GET", Path: "/user/{id}"})
	catalog.Add(problem.CatalogEntry{ID: "manual", TypeURI: "https://x/manual", Title: "Manual", Status: 500})
	_ = catalog.AddGenerics()
	entry, found := catalog.Lookup("entity_not_found")

	// Assert
	fmt.Println(len(catalog.Entries()), found, len(entry.Endpoints), catalog.Portal().Module)
	fmt.Println(catalog.ToCRDContent()[0]["id"])
	// Output:
	// 7 true 0 api
	// entity_not_found
}

func ExampleNewCatalog() {
	// Arrange
	entry := problem.CatalogEntry{ID: "manual", TypeURI: "https://x/manual", Title: "Manual", Status: 500}

	// Act
	catalog := problem.NewCatalog(examplePortal(), entry)

	// Assert
	fmt.Println(len(catalog.Entries()))
	// Output: 1
}

func ExampleCatalog_ToResource() {
	// Arrange
	catalog := problem.NewCatalog(examplePortal())
	_ = catalog.AddType(problem.Conflict(), problem.CatalogEndpoint{Method: "POST", Path: "/user"})

	// Act
	resource, err := catalog.ToResource(exampleIdentity())

	// Assert
	fmt.Println(err, resource.Kind, resource.Metadata.Name, resource.Metadata.Namespace)
	fmt.Println(resource.Spec.Problems[0]["type"])
	// Output:
	// <nil> Problem user.api.raichu.v1 go
	// https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/conflict
}

func ExampleResource() {
	// Arrange
	catalog := problem.NewCatalog(examplePortal())
	_ = catalog.AddType(problem.Unauthenticated())
	resource, _ := catalog.ToResource(exampleIdentity())

	// Act
	manifest, _ := json.Marshal(resource)

	// Assert
	fmt.Println(string(manifest))
	// Output: {"apiVersion":"atomi.cloud/v1alpha1","kind":"Problem","metadata":{"name":"user.api.raichu.v1","namespace":"go"},"spec":{"platform":"go","service":"user","module":"api","landscape":"raichu","version":"v1","problems":[{"endpoints":[],"id":"unauthenticated","recoverable":true,"schema":{"not":{}},"status":401,"title":"Unauthenticated","type":"https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/unauthenticated"}]}}
}

func ExampleResourceIdentity() {
	// Arrange
	identity := exampleIdentity()

	// Act
	resource, _ := problem.NewCatalog(examplePortal()).ToResource(identity)

	// Assert
	fmt.Println(resource.Spec.ResourceIdentity == identity)
	// Output: true
}

func ExampleResourceMetadata() {
	// Arrange
	catalog := problem.NewCatalog(examplePortal())

	// Act
	resource, _ := catalog.ToResource(exampleIdentity())

	// Assert
	fmt.Println(resource.Metadata == problem.ResourceMetadata{Name: "user.api.raichu.v1", Namespace: "go"})
	// Output: true
}

func ExampleResourceSpec() {
	// Arrange
	catalog := problem.NewCatalog(examplePortal())
	_ = catalog.AddGenerics()

	// Act
	resource, _ := catalog.ToResource(exampleIdentity())
	spec := resource.Spec

	// Assert
	fmt.Println(spec.Version, len(spec.Problems))
	// Output: v1 6
}

func ExampleInvalidResourceError() {
	// Arrange
	catalog := problem.NewCatalog(examplePortal())
	identity := exampleIdentity()
	identity.Service = "billing"
	var invalid *problem.InvalidResourceError

	// Act
	_, err := catalog.ToResource(identity)

	// Assert
	fmt.Println(errors.As(err, &invalid), invalid.Field)
	fmt.Println(err)
	// Output:
	// true service
	// problem resource service must match the catalog portal "user", got "billing"
}

func ExampleTransformOptions() {
	// Arrange
	registry, _ := problem.NewRegistry(examplePortal(), problem.EntityNotFound())
	options := problem.TransformOptions{Portal: examplePortal(), Registry: registry, DefaultStatus: 500, DefaultVersion: "v1"}

	// Act
	envelope := problem.FromObject(map[string]any{"problemId": "entity_not_found", "data": map[string]any{"entityType": "user", "id": "42"}}, options)

	// Assert
	fmt.Println(envelope.Status, envelope.Data)
	// Output: 404 map[entityType:user id:42]
}

func ExampleDefaultTransformOptions() {
	// Arrange
	options := problem.DefaultTransformOptions()

	// Act
	uri, _ := problem.TypeURI(options.Portal, options.DefaultVersion, problem.UncataloguedProblemID)

	// Assert
	fmt.Println(options.DefaultStatus, options.Registry == nil, uri)
	// Output: 500 true https://local.atomi.cloud/docs/local/go/app/core/v1/uncatalogued
}

func ExampleFromObject() {
	// Arrange
	cause := errors.New("disk full")

	// Act
	envelope := problem.FromObject(cause, problem.DefaultTransformOptions())

	// Assert
	fmt.Println(envelope.Status, *envelope.Detail, envelope.Data == nil)
	// Output: 500 disk full true
}

type printSink struct{}

func (printSink) Capture(_ context.Context, captured problem.Problem) error {
	fmt.Println("captured", captured.Title)
	return nil
}

func ExampleErrorSink() {
	// Arrange
	var sink problem.ErrorSink = printSink{}
	local := problem.NewLocalError(sink)

	// Act
	_, err := local.Wrap(context.Background(), errors.New("boom"), "stack")

	// Assert
	fmt.Println(err)
	// Output:
	// captured Local Error
	// <nil>
}

func ExampleNoopErrorSink() {
	// Arrange
	sink := problem.NoopErrorSink{}

	// Act
	err := sink.Capture(context.Background(), problem.Problem{})

	// Assert
	fmt.Println(err)
	// Output: <nil>
}

func ExampleLocalError() {
	// Arrange
	local := problem.LocalError{Sink: problem.NoopErrorSink{}, Portal: problem.LocalErrorPortal()}

	// Act
	envelope, _ := local.Wrap(context.Background(), errors.New("boom"), "goroutine 1 [running]")

	// Assert
	fmt.Println(envelope.Type)
	fmt.Println(envelope.Data["message"])
	// Output:
	// https://local.atomi.cloud/docs/local/go/app/core/v1/local_error
	// boom
}

func ExampleNewLocalError() {
	// Arrange
	sink := problem.NoopErrorSink{}

	// Act
	local := problem.NewLocalError(sink)

	// Assert
	fmt.Println(local.Portal == problem.LocalErrorPortal())
	// Output: true
}

func ExampleNewLocalErrorWithPortal() {
	// Arrange
	sink := problem.NoopErrorSink{}

	// Act
	local := problem.NewLocalErrorWithPortal(sink, examplePortal())
	envelope, _ := local.Wrap(context.Background(), errors.New("boom"), "")

	// Assert
	fmt.Println(envelope.Type)
	// Output: https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/local_error
}
