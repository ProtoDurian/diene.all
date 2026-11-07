package problem_test

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

type recordingSink struct {
	captured []problem.Problem
	err      error
}

func (s *recordingSink) Capture(_ context.Context, envelope problem.Problem) error {
	s.captured = append(s.captured, envelope)
	return s.err
}

func TestNoopErrorSinkCapture(t *testing.T) {
	t.Parallel()
	// Arrange
	sink := problem.NoopErrorSink{}

	// Act
	err := sink.Capture(context.Background(), problem.Problem{})
	// Assert
	if err != nil {
		t.Fatalf("Capture = %v", err)
	}
}

func TestLocalErrorWrap(t *testing.T) {
	t.Parallel()
	text := func(value string) *string { return &value }
	sinkDown := errors.New("sink down")
	cases := []struct {
		name         string
		portal       *problem.ErrorPortal
		sink         *recordingSink
		cause        error
		stack        string
		want         problem.Problem
		wantErr      error
		wantCaptured int
	}{
		{
			name:  "captures cause and stack",
			sink:  &recordingSink{},
			cause: errors.New("boom"),
			stack: "stack-trace",
			want: problem.Problem{
				Type: "https://local.atomi.cloud/docs/local/go/app/core/v1/local_error", Title: "Local Error", Status: 500,
				Detail: text("boom"), Data: map[string]any{"message": "boom", "stackTrace": "stack-trace"},
			},
			wantCaptured: 1,
		},
		{
			name: "nil cause keeps an empty detail",
			sink: &recordingSink{},
			want: problem.Problem{
				Type: "https://local.atomi.cloud/docs/local/go/app/core/v1/local_error", Title: "Local Error", Status: 500,
				Detail: text(""), Data: map[string]any{"message": "", "stackTrace": ""},
			},
			wantCaptured: 1,
		},
		{
			name:  "returns the envelope with a capture failure",
			sink:  &recordingSink{err: sinkDown},
			cause: errors.New("boom"),
			want: problem.Problem{
				Type: "https://local.atomi.cloud/docs/local/go/app/core/v1/local_error", Title: "Local Error", Status: 500,
				Detail: text("boom"), Data: map[string]any{"message": "boom", "stackTrace": ""},
			},
			wantErr:      sinkDown,
			wantCaptured: 1,
		},
		{
			name:   "invalid portal falls back to about:blank",
			portal: &problem.ErrorPortal{},
			sink:   &recordingSink{},
			cause:  errors.New("boom"),
			want: problem.Problem{
				Type: "about:blank", Title: "Local Error", Status: 500,
				Detail: text("boom"), Data: map[string]any{"message": "boom", "stackTrace": ""},
			},
			wantCaptured: 1,
		},
		{
			name:  "nil sink",
			cause: errors.New("boom"),
			want: problem.Problem{
				Type: "https://local.atomi.cloud/docs/local/go/app/core/v1/local_error", Title: "Local Error", Status: 500,
				Detail: text("boom"), Data: map[string]any{"message": "boom", "stackTrace": ""},
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			var sink problem.ErrorSink
			if tc.sink != nil {
				sink = tc.sink
			}
			local := problem.NewLocalError(sink)
			if tc.portal != nil {
				local = problem.NewLocalErrorWithPortal(sink, *tc.portal)
			}

			// Act
			got, err := local.Wrap(context.Background(), tc.cause, tc.stack)

			// Assert
			if !errors.Is(err, tc.wantErr) || !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("Wrap = %+v, %v", got, err)
			}
			if tc.sink != nil && len(tc.sink.captured) != tc.wantCaptured {
				t.Fatalf("captured %d, want %d", len(tc.sink.captured), tc.wantCaptured)
			}
		})
	}
}
