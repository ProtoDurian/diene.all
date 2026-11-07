package problem_test

import (
	"errors"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

func testPortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.example.atomi.cloud",
		Landscape: "raichu",
		Platform:  "go",
		Service:   "user",
		Module:    "api",
	}
}

func TestTypeURI(t *testing.T) {
	t.Parallel()
	withPortal := func(change func(*problem.ErrorPortal)) problem.ErrorPortal {
		portal := testPortal()
		change(&portal)
		return portal
	}
	cases := []struct {
		name        string
		portal      problem.ErrorPortal
		version     string
		id          string
		want        string
		wantSegment string
	}{
		{name: "expands template", portal: testPortal(), version: "v1", id: "entity_not_found", want: "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v1/entity_not_found"},
		{name: "keeps version", portal: testPortal(), version: "v2", id: "conflict", want: "https://docs.example.atomi.cloud/docs/raichu/go/user/api/v2/conflict"},
		{name: "empty scheme", portal: withPortal(func(p *problem.ErrorPortal) { p.Scheme = "" }), version: "v1", id: "x", wantSegment: "scheme"},
		{name: "invalid scheme", portal: withPortal(func(p *problem.ErrorPortal) { p.Scheme = "ht tp" }), version: "v1", id: "x", wantSegment: "scheme"},
		{name: "scheme with colon", portal: withPortal(func(p *problem.ErrorPortal) { p.Scheme = "a:b" }), version: "v1", id: "x", wantSegment: "scheme"},
		{name: "empty host", portal: withPortal(func(p *problem.ErrorPortal) { p.Host = "" }), version: "v1", id: "x", wantSegment: "host"},
		{name: "host with path", portal: withPortal(func(p *problem.ErrorPortal) { p.Host = "h/x" }), version: "v1", id: "x", wantSegment: "host"},
		{name: "host with user", portal: withPortal(func(p *problem.ErrorPortal) { p.Host = "u@h" }), version: "v1", id: "x", wantSegment: "host"},
		{name: "host with query", portal: withPortal(func(p *problem.ErrorPortal) { p.Host = "h?x" }), version: "v1", id: "x", wantSegment: "host"},
		{name: "host with fragment", portal: withPortal(func(p *problem.ErrorPortal) { p.Host = "h#x" }), version: "v1", id: "x", wantSegment: "host"},
		{name: "unparsable host", portal: withPortal(func(p *problem.ErrorPortal) { p.Host = "%zz" }), version: "v1", id: "x", wantSegment: "host"},
		{name: "empty landscape", portal: withPortal(func(p *problem.ErrorPortal) { p.Landscape = "" }), version: "v1", id: "x", wantSegment: "landscape"},
		{name: "platform with slash", portal: withPortal(func(p *problem.ErrorPortal) { p.Platform = "a/b" }), version: "v1", id: "x", wantSegment: "platform"},
		{name: "empty service", portal: withPortal(func(p *problem.ErrorPortal) { p.Service = "" }), version: "v1", id: "x", wantSegment: "service"},
		{name: "empty module", portal: withPortal(func(p *problem.ErrorPortal) { p.Module = "" }), version: "v1", id: "x", wantSegment: "module"},
		{name: "empty version", portal: testPortal(), version: "", id: "x", wantSegment: "version"},
		{name: "id needing escape", portal: testPortal(), version: "v1", id: "a b", wantSegment: "id"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			var segmentErr *problem.InvalidSegmentError

			// Act
			got, err := problem.TypeURI(tc.portal, tc.version, tc.id)

			// Assert
			if tc.wantSegment == "" {
				if err != nil || got != tc.want {
					t.Fatalf("TypeURI = %q, %v; want %q", got, err, tc.want)
				}
				return
			}
			if !errors.As(err, &segmentErr) || segmentErr.Name != tc.wantSegment || got != "" {
				t.Fatalf("TypeURI = %q, %v; want %s segment error", got, err, tc.wantSegment)
			}
		})
	}
}

func TestInvalidSegmentErrorMessage(t *testing.T) {
	t.Parallel()
	// Arrange
	err := &problem.InvalidSegmentError{Name: "id", Value: "a/b"}

	// Act
	message := err.Error()

	// Assert
	if message != `problem type URI segment id must be a non-empty single path segment, got "a/b"` {
		t.Fatalf("unexpected message %q", message)
	}
}

func TestLocalErrorPortalBuildsTypeURI(t *testing.T) {
	t.Parallel()
	// Arrange
	portal := problem.LocalErrorPortal()

	// Act
	got, err := problem.TypeURI(portal, "v1", "local_error")

	// Assert
	if err != nil || got != "https://local.atomi.cloud/docs/local/go/app/core/v1/local_error" {
		t.Fatalf("TypeURI = %q, %v", got, err)
	}
}
