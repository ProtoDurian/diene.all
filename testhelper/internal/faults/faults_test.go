package faults_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	probtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
	"github.com/ProtoDurian/diene.go-interfaces/testhelper/internal/faults"
)

const typePrefix = "https://docs.diene.atomicloud.com/docs/diene/go/interfaces/testhelper/v1/"

func TestIntrinsicFaults(t *testing.T) {
	// Arrange
	cases := []struct {
		name   string
		mint   func() error
		id     string
		status int
		detail string
	}{
		{"path-not-found", func() error { return faults.PathNotFound("/missing") }, "path-not-found", 404, "/missing"},
		{"directory-not-empty", func() error { return faults.DirectoryNotEmpty("/dir") }, "directory-not-empty", 409, "/dir"},
		{"path-is-directory", func() error { return faults.PathIsDirectory("/dir") }, "path-is-directory", 409, "/dir"},
		{"path-is-file", func() error { return faults.PathIsFile("/file") }, "path-is-file", 409, "/file"},
		{"not-a-directory", func() error { return faults.NotADirectory("/file") }, "not-a-directory", 409, "/file"},
		{"terminal-result-not-scripted", func() error { return faults.TerminalNotScripted("tool") }, "terminal-result-not-scripted", 500, "tool"},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			// Act
			err := testCase.mint()

			// Assert
			probtest.AssertError(
				t, err,
				probtest.ExpectType(typePrefix+testCase.id),
				probtest.ExpectID(testCase.id),
				probtest.ExpectStatus(testCase.status),
				probtest.ExpectDetail(testCase.detail),
				probtest.ExpectData(map[string]any{"id": testCase.id}),
			)
		})
	}
}

func TestNormalize(t *testing.T) {
	// Arrange
	cause := errors.New("boom")
	original := faults.PathNotFound("/keep")
	cases := []struct {
		name string
		in   error
		is   error
	}{
		{"nil stays nil", nil, nil},
		{"plain error is wrapped and still unwraps", cause, cause},
		{"problem error passes through", original, original},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			// Act
			normalized := faults.Normalize(testCase.in)

			// Assert
			if testCase.in == nil {
				if normalized != nil {
					t.Fatalf("expected nil, got %v", normalized)
				}
				return
			}
			var problemErr *problem.Error
			if !errors.As(normalized, &problemErr) || problemErr == nil {
				t.Fatalf("expected a *problem.Error, got %#v", normalized)
			}
			if !errors.Is(normalized, testCase.is) {
				t.Fatalf("expected %v in the chain of %v", testCase.is, normalized)
			}
		})
	}
}
