// Package testhelper provides Problem assertions and fixtures for tests of code that returns problem errors.
package testhelper

import (
	"errors"
	"fmt"
	"reflect"
	"strings"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

// TestingT is the subset of *testing.T the assertions use.
type TestingT interface {
	Helper()
	Fatalf(format string, args ...any)
}

// Option checks one field of a [problem.Problem]; only the given options are checked.
type Option func(problem.Problem) error

// ExpectType asserts the envelope's Type equals want.
func ExpectType(want string) Option {
	return func(actual problem.Problem) error {
		if actual.Type != want {
			return fmt.Errorf("type mismatch: expected %q, got %q", want, actual.Type)
		}
		return nil
	}
}

// ExpectID asserts the last path segment of the envelope's Type equals want.
func ExpectID(want string) Option {
	return func(actual problem.Problem) error {
		got := actual.Type
		if index := strings.LastIndex(got, "/"); index >= 0 {
			got = got[index+1:]
		}
		if got != want {
			return fmt.Errorf("id mismatch: expected %q, got %q (from type %q)", want, got, actual.Type)
		}
		return nil
	}
}

// ExpectTitle asserts the envelope's Title equals want.
func ExpectTitle(want string) Option {
	return func(actual problem.Problem) error {
		if actual.Title != want {
			return fmt.Errorf("title mismatch: expected %q, got %q", want, actual.Title)
		}
		return nil
	}
}

// ExpectStatus asserts the envelope's Status equals want.
func ExpectStatus(want int) Option {
	return func(actual problem.Problem) error {
		if actual.Status != want {
			return fmt.Errorf("status mismatch: expected %d, got %d", want, actual.Status)
		}
		return nil
	}
}

// ExpectRecoverable asserts the envelope's Recoverable flag equals want.
//
//nolint:revive // want is a matched value, not a control flag.
func ExpectRecoverable(want bool) Option {
	return func(actual problem.Problem) error {
		if actual.Recoverable != want {
			return fmt.Errorf("recoverable mismatch: expected %t, got %t", want, actual.Recoverable)
		}
		return nil
	}
}

// ExpectDetail asserts the envelope's Detail is present and equals want.
func ExpectDetail(want string) Option {
	return func(actual problem.Problem) error {
		if actual.Detail == nil || *actual.Detail != want {
			got := "<nil>"
			if actual.Detail != nil {
				got = fmt.Sprintf("%q", *actual.Detail)
			}
			return fmt.Errorf("detail mismatch: expected %q, got %s", want, got)
		}
		return nil
	}
}

// ExpectInstance asserts the envelope's Instance is present and equals want.
func ExpectInstance(want string) Option {
	return func(actual problem.Problem) error {
		if actual.Instance == nil || *actual.Instance != want {
			got := "<nil>"
			if actual.Instance != nil {
				got = fmt.Sprintf("%q", *actual.Instance)
			}
			return fmt.Errorf("instance mismatch: expected %q, got %s", want, got)
		}
		return nil
	}
}

// ExpectData asserts the envelope's Data deep-equals want; nil means no data.
func ExpectData(want map[string]any) Option {
	return func(actual problem.Problem) error {
		if (len(want) > 0 || len(actual.Data) > 0) && !reflect.DeepEqual(actual.Data, want) {
			return fmt.Errorf("data mismatch: expected %v, got %v", want, actual.Data)
		}
		return nil
	}
}

// CheckProblem returns the first mismatch between actual and opts, or nil.
func CheckProblem(actual problem.Problem, opts ...Option) error {
	for _, opt := range opts {
		if err := opt(actual); err != nil {
			return err
		}
	}
	return nil
}

// AssertProblem fails t when actual does not match opts.
func AssertProblem(t TestingT, actual problem.Problem, opts ...Option) {
	t.Helper()
	if err := CheckProblem(actual, opts...); err != nil {
		t.Fatalf("problem assertion failed: %v", err)
	}
}

// CheckError recovers the [problem.Problem] carried by err and checks it against opts.
func CheckError(err error, opts ...Option) (problem.Problem, error) {
	if err == nil {
		return problem.Problem{}, errors.New("expected a problem-typed error, got nil")
	}
	var problemErr *problem.Error
	if !errors.As(err, &problemErr) {
		return problem.Problem{}, fmt.Errorf("expected a *problem.Error, got %T", err)
	}
	// errors.As also matches a typed-nil *problem.Error; reading it would panic.
	if problemErr == nil {
		return problem.Problem{}, fmt.Errorf("expected a non-nil *problem.Error, got a typed-nil %T", err)
	}
	if checkErr := CheckProblem(problemErr.Problem, opts...); checkErr != nil {
		return problem.Problem{}, checkErr
	}
	return problemErr.Problem, nil
}

// AssertError fails t unless err carries a problem matching opts, and returns that problem.
func AssertError(t TestingT, err error, opts ...Option) problem.Problem {
	t.Helper()
	envelope, checkErr := CheckError(err, opts...)
	if checkErr != nil {
		t.Fatalf("problem-error assertion failed: %v", checkErr)
	}
	return envelope
}

// SampleErrorPortal returns a valid [problem.ErrorPortal] for tests.
func SampleErrorPortal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.raichu.cluster.atomi.cloud",
		Landscape: "raichu",
		Platform:  "go",
		Service:   "user",
		Module:    "api",
	}
}

// SampleProblem returns a valid entity_not_found [problem.Problem] built from [SampleErrorPortal].
func SampleProblem() problem.Problem {
	registry, _ := problem.NewRegistry(SampleErrorPortal(), problem.EntityNotFound())
	envelope, _ := registry.NewProblem("entity_not_found", map[string]any{"entityType": "user", "id": "42"})
	return envelope
}
