package problem_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

type envelopeFixture struct {
	RFC9457Members    []string       `json:"rfc9457Members"`
	Extensions        []string       `json:"extensions"`
	Sample            map[string]any `json:"sample"`
	SampleWithoutData map[string]any `json:"sampleWithoutData"`
}

type wireEndpoint struct {
	Method string `json:"method"`
	Path   string `json:"path"`
}

type wireProblemRow struct {
	ID          string         `json:"id"`
	Type        string         `json:"type"`
	Title       string         `json:"title"`
	Status      int            `json:"status"`
	Recoverable bool           `json:"recoverable"`
	Schema      map[string]any `json:"schema"`
	Endpoints   []wireEndpoint `json:"endpoints"`
}

type catalogEntryFixture struct {
	RequiredFields []string       `json:"requiredFields"`
	NoDataSchema   map[string]any `json:"noDataSchema"`
	Sample         wireProblemRow `json:"sample"`
}

type typeURIFixture struct {
	Template        string            `json:"template"`
	Segments        map[string]string `json:"segments"`
	ExpectedTypeURI string            `json:"expectedTypeUri"`
}

func loadFixture(t *testing.T, name string, target any) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "fixtures", "wire-format", name)) //nolint:gosec // fixed in-repo fixture path
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	if err := json.Unmarshal(raw, target); err != nil {
		t.Fatalf("parse fixture %s: %v", name, err)
	}
}

func TestWireFormatEnvelope(t *testing.T) {
	t.Parallel()
	var fixture envelopeFixture
	loadFixture(t, "envelope.json", &fixture)
	cases := []struct {
		name       string
		sample     map[string]any
		wantFields []string
	}{
		{name: "with data", sample: fixture.Sample, wantFields: append(append([]string{}, fixture.RFC9457Members...), fixture.Extensions...)},
		{name: "without data", sample: fixture.SampleWithoutData, wantFields: []string{"type", "title", "status", "recoverable"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			encoded, _ := json.Marshal(tc.sample)
			var envelope problem.Problem

			// Act
			unmarshalErr := json.Unmarshal(encoded, &envelope)
			roundTripped, marshalErr := json.Marshal(envelope)
			var got map[string]any
			_ = json.Unmarshal(roundTripped, &got)

			// Assert
			if unmarshalErr != nil || marshalErr != nil || !reflect.DeepEqual(got, tc.sample) || len(got) != len(tc.wantFields) {
				t.Fatalf("round trip = %v (%v, %v), want %v", got, unmarshalErr, marshalErr, tc.sample)
			}
			for _, field := range tc.wantFields {
				if _, ok := got[field]; !ok {
					t.Fatalf("wire form missing %q", field)
				}
			}
		})
	}
}

func TestWireFormatCatalogEntry(t *testing.T) {
	t.Parallel()
	var fixture catalogEntryFixture
	loadFixture(t, "catalog-entry.json", &fixture)
	sample := fixture.Sample
	endpoints := make([]problem.CatalogEndpoint, 0, len(sample.Endpoints))
	for _, endpoint := range sample.Endpoints {
		endpoints = append(endpoints, problem.CatalogEndpoint{Method: endpoint.Method, Path: endpoint.Path})
	}
	cases := []struct {
		name       string
		schema     map[string]any
		wantSchema map[string]any
	}{
		{name: "with data schema", schema: sample.Schema, wantSchema: sample.Schema},
		{name: "without data schema", schema: nil, wantSchema: fixture.NoDataSchema},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			entry := problem.CatalogEntry{ID: sample.ID, TypeURI: sample.Type, Title: sample.Title, Status: sample.Status, Recoverable: sample.Recoverable, DataSchema: tc.schema, Endpoints: endpoints}

			// Act
			encoded, err := json.Marshal(entry.ToCRDContent())
			var got map[string]any
			_ = json.Unmarshal(encoded, &got)

			// Assert
			if err != nil || len(got) != len(fixture.RequiredFields) {
				t.Fatalf("entry = %v, %v", got, err)
			}
			for _, field := range fixture.RequiredFields {
				if _, ok := got[field]; !ok {
					t.Fatalf("entry missing %q", field)
				}
			}
			if !reflect.DeepEqual(got["schema"], tc.wantSchema) || got["id"] != sample.ID || got["type"] != sample.Type {
				t.Fatalf("entry = %v", got)
			}
		})
	}
}

func TestWireFormatTypeURI(t *testing.T) {
	t.Parallel()
	// Arrange
	var fixture typeURIFixture
	loadFixture(t, "type-uri.json", &fixture)
	segments := fixture.Segments
	portal := problem.ErrorPortal{
		Scheme:    segments["scheme"],
		Host:      segments["host"],
		Landscape: segments["landscape"],
		Platform:  segments["platform"],
		Service:   segments["service"],
		Module:    segments["module"],
	}

	// Act
	got, err := problem.TypeURI(portal, segments["version"], segments["id"])

	// Assert
	if err != nil || got != fixture.ExpectedTypeURI {
		t.Fatalf("TypeURI = %q, %v; want %q", got, err, fixture.ExpectedTypeURI)
	}
	if fixture.Template != "{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}" {
		t.Fatalf("fixture template drifted: %q", fixture.Template)
	}
}
