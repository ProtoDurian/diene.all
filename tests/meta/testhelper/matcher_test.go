package testhelper_test

import (
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
	"github.com/ProtoDurian/diene.go-errors-problems/testhelper"
)

type recordingT struct {
	failed  bool
	message string
}

func (*recordingT) Helper() {}

func (r *recordingT) Fatalf(format string, args ...any) {
	r.failed = true
	r.message = fmt.Sprintf(format, args...)
}

func goodProblem() problem.Problem {
	detail, instance := "missing", "/user/42"
	return problem.Problem{
		Type:        "https://h/docs/l/p/s/m/v1/entity_not_found",
		Title:       "Entity Not Found",
		Status:      404,
		Detail:      &detail,
		Instance:    &instance,
		Recoverable: false,
		Data:        map[string]any{"entityType": "user", "id": "42"},
	}
}

func TestCheckProblem(t *testing.T) {
	t.Parallel()
	good := goodProblem()
	noData := problem.Problem{Type: "https://h/docs/l/p/s/m/v1/unauthorized", Title: "Unauthorized", Status: 403}
	cases := []struct {
		name     string
		actual   problem.Problem
		options  []testhelper.Option
		wantFail string
	}{
		{
			name:   "every field matches",
			actual: good,
			options: []testhelper.Option{
				testhelper.ExpectType(good.Type), testhelper.ExpectID("entity_not_found"), testhelper.ExpectTitle(good.Title),
				testhelper.ExpectStatus(404), testhelper.ExpectRecoverable(false), testhelper.ExpectDetail("missing"),
				testhelper.ExpectInstance("/user/42"), testhelper.ExpectData(map[string]any{"entityType": "user", "id": "42"}),
			},
		},
		{name: "subset matches", actual: good, options: []testhelper.Option{testhelper.ExpectStatus(404)}},
		{name: "nil data matches no data", actual: noData, options: []testhelper.Option{testhelper.ExpectData(nil)}},
		{name: "empty data matches no data", actual: problem.Problem{Data: map[string]any{}}, options: []testhelper.Option{testhelper.ExpectData(nil)}},
		{name: "id without slash", actual: problem.Problem{Type: "conflict"}, options: []testhelper.Option{testhelper.ExpectID("conflict")}},
		{name: "wrong type", actual: good, options: []testhelper.Option{testhelper.ExpectType("https://other")}, wantFail: "type mismatch"},
		{name: "wrong id", actual: good, options: []testhelper.Option{testhelper.ExpectID("conflict")}, wantFail: "id mismatch"},
		{name: "wrong title", actual: good, options: []testhelper.Option{testhelper.ExpectTitle("Wrong")}, wantFail: "title mismatch"},
		{name: "wrong status", actual: good, options: []testhelper.Option{testhelper.ExpectStatus(500)}, wantFail: "status mismatch"},
		{name: "wrong recoverable", actual: good, options: []testhelper.Option{testhelper.ExpectRecoverable(true)}, wantFail: "recoverable mismatch"},
		{name: "wrong detail", actual: good, options: []testhelper.Option{testhelper.ExpectDetail("other")}, wantFail: "detail mismatch"},
		{name: "absent detail", actual: noData, options: []testhelper.Option{testhelper.ExpectDetail("missing")}, wantFail: "got <nil>"},
		{name: "wrong instance", actual: good, options: []testhelper.Option{testhelper.ExpectInstance("/other")}, wantFail: "instance mismatch"},
		{name: "absent instance", actual: noData, options: []testhelper.Option{testhelper.ExpectInstance("/x")}, wantFail: "got <nil>"},
		{name: "wrong data", actual: good, options: []testhelper.Option{testhelper.ExpectData(map[string]any{"entityType": "user", "id": "99"})}, wantFail: "data mismatch"},
		{name: "data where none expected", actual: good, options: []testhelper.Option{testhelper.ExpectData(nil)}, wantFail: "data mismatch"},
		{name: "first mismatch wins", actual: good, options: []testhelper.Option{testhelper.ExpectStatus(500), testhelper.ExpectTitle("Wrong")}, wantFail: "status mismatch"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			actual := tc.actual

			// Act
			err := testhelper.CheckProblem(actual, tc.options...)

			// Assert
			if tc.wantFail == "" && err != nil {
				t.Fatalf("known-good failed: %v", err)
			}
			if tc.wantFail != "" && (err == nil || !strings.Contains(err.Error(), tc.wantFail)) {
				t.Fatalf("known-bad = %v, want %q", err, tc.wantFail)
			}
		})
	}
}

func TestAssertProblem(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name     string
		option   testhelper.Option
		wantFail bool
	}{
		{name: "known-good", option: testhelper.ExpectStatus(404)},
		{name: "known-bad", option: testhelper.ExpectStatus(500), wantFail: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			recorder := &recordingT{}

			// Act
			testhelper.AssertProblem(recorder, goodProblem(), tc.option)

			// Assert
			if recorder.failed != tc.wantFail || (tc.wantFail && !strings.Contains(recorder.message, "problem assertion failed")) {
				t.Fatalf("failed = %t, message %q", recorder.failed, recorder.message)
			}
		})
	}
}

func TestCheckError(t *testing.T) {
	t.Parallel()
	var typedNil *problem.Error
	cases := []struct {
		name     string
		err      error
		options  []testhelper.Option
		wantFail string
	}{
		{name: "wrapped problem error", err: fmt.Errorf("ctx: %w", problem.NewError(goodProblem())), options: []testhelper.Option{testhelper.ExpectID("entity_not_found")}},
		{name: "nil error", err: nil, wantFail: "got nil"},
		{name: "plain error", err: errors.New("plain"), wantFail: "expected a *problem.Error"},
		{name: "typed-nil problem error", err: typedNil, wantFail: "typed-nil"},
		{name: "field mismatch", err: problem.NewError(goodProblem()), options: []testhelper.Option{testhelper.ExpectStatus(500)}, wantFail: "status mismatch"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			err := tc.err

			// Act
			recovered, checkErr := testhelper.CheckError(err, tc.options...)

			// Assert
			if tc.wantFail == "" && (checkErr != nil || !recovered.Equal(goodProblem())) {
				t.Fatalf("known-good = %+v, %v", recovered, checkErr)
			}
			if tc.wantFail != "" && (checkErr == nil || !strings.Contains(checkErr.Error(), tc.wantFail) || !recovered.Equal(problem.Problem{})) {
				t.Fatalf("known-bad = %+v, %v; want %q", recovered, checkErr, tc.wantFail)
			}
		})
	}
}

func TestAssertError(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name       string
		err        error
		wantFail   bool
		wantStatus int
	}{
		{name: "known-good", err: problem.NewError(goodProblem()), wantStatus: 404},
		{name: "known-bad", err: errors.New("plain"), wantFail: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			recorder := &recordingT{}

			// Act
			recovered := testhelper.AssertError(recorder, tc.err, testhelper.ExpectID("entity_not_found"))

			// Assert
			if recorder.failed != tc.wantFail || recovered.Status != tc.wantStatus {
				t.Fatalf("failed = %t (%q), status %d", recorder.failed, recorder.message, recovered.Status)
			}
		})
	}
}

func TestAssertionsAcceptEveryGenericProblem(t *testing.T) {
	t.Parallel()
	registry, _ := problem.NewRegistry(testhelper.SampleErrorPortal())
	_ = problem.RegisterGenerics(registry)
	for _, problemType := range problem.GenericProblems() {
		t.Run(problemType.ID, func(t *testing.T) {
			t.Parallel()
			// Arrange
			envelope, _ := registry.NewProblem(problemType.ID, nil)

			// Act
			_, err := testhelper.CheckError(
				problem.NewError(envelope),
				testhelper.ExpectID(problemType.ID),
				testhelper.ExpectStatus(problemType.Status),
				testhelper.ExpectRecoverable(problemType.Recoverable),
				testhelper.ExpectData(nil),
			)
			// Assert
			if err != nil {
				t.Fatalf("generic %s: %v", problemType.ID, err)
			}
		})
	}
}
