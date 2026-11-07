package testhelper_test

import (
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
	"github.com/ProtoDurian/diene.go-errors-problems/testhelper"
)

func TestSampleErrorPortalBuildsTypeURI(t *testing.T) {
	t.Parallel()
	// Arrange
	portal := testhelper.SampleErrorPortal()

	// Act
	uri, err := problem.TypeURI(portal, "v1", "entity_not_found")

	// Assert
	if err != nil || uri != "https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found" {
		t.Fatalf("TypeURI = %q, %v", uri, err)
	}
}

func TestSampleProblemIsTheGenericEntityNotFound(t *testing.T) {
	t.Parallel()
	// Arrange
	registry, _ := problem.NewRegistry(testhelper.SampleErrorPortal(), problem.EntityNotFound())
	want, _ := registry.NewProblem("entity_not_found", map[string]any{"entityType": "user", "id": "42"})

	// Act
	sample := testhelper.SampleProblem()

	// Assert
	err := testhelper.CheckProblem(
		sample,
		testhelper.ExpectType(want.Type),
		testhelper.ExpectID("entity_not_found"),
		testhelper.ExpectTitle("Entity Not Found"),
		testhelper.ExpectStatus(404),
		testhelper.ExpectRecoverable(false),
		testhelper.ExpectData(map[string]any{"entityType": "user", "id": "42"}),
	)
	if err != nil || !sample.Equal(want) {
		t.Fatalf("sample = %+v, %v", sample, err)
	}
}
