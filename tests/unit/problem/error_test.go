package problem_test

import (
	"errors"
	"fmt"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

func TestErrorMessageAndUnwrap(t *testing.T) {
	t.Parallel()
	envelope := problem.Problem{Type: "t", Title: "Conflict", Status: 409}
	cause := errors.New("cause")
	cases := []struct {
		name        string
		err         *problem.Error
		wantMessage string
		wantCause   error
	}{
		{name: "plain", err: problem.NewError(envelope), wantMessage: "Problem(t, 409, Conflict)"},
		{name: "wrapped", err: problem.WrapError(envelope, cause), wantMessage: "Problem(t, 409, Conflict): cause", wantCause: cause},
		{name: "nil receiver", err: nil, wantMessage: "<nil problem error>"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			err := tc.err

			// Act
			message := err.Error()
			unwrapped := err.Unwrap()

			// Assert
			if message != tc.wantMessage || !errors.Is(unwrapped, tc.wantCause) {
				t.Fatalf("Error = %q, Unwrap = %v", message, unwrapped)
			}
		})
	}
}

func TestErrorWorksWithErrorsAsAndIs(t *testing.T) {
	t.Parallel()
	// Arrange
	cause := errors.New("cause")
	envelope := problem.Problem{Type: "t", Title: "Conflict", Status: 409}
	var problemErr *problem.Error

	// Act
	err := fmt.Errorf("saving: %w", problem.WrapError(envelope, cause))

	// Assert
	if !errors.As(err, &problemErr) || problemErr.Problem.Status != 409 || !errors.Is(err, cause) {
		t.Fatalf("chain not traversable: %v", err)
	}
}
