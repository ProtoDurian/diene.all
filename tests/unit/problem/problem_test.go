package problem_test

import (
	"encoding/json"
	"reflect"
	"testing"

	"github.com/ProtoDurian/diene.go-errors-problems/lib/problem"
)

func TestProblemMarshalJSON(t *testing.T) {
	t.Parallel()
	empty := ""
	detail, instance := "User 42 does not exist", "/user/42"
	cases := []struct {
		name     string
		envelope problem.Problem
		want     string
	}{
		{
			name:     "every member",
			envelope: problem.Problem{Type: "t", Title: "T", Status: 404, Detail: &detail, Instance: &instance, Recoverable: false, Data: map[string]any{"id": "42"}},
			want:     `{"data":{"id":"42"},"detail":"User 42 does not exist","instance":"/user/42","recoverable":false,"status":404,"title":"T","type":"t"}`,
		},
		{
			name:     "nil data is omitted",
			envelope: problem.Problem{Type: "t", Title: "T", Status: 403},
			want:     `{"recoverable":false,"status":403,"title":"T","type":"t"}`,
		},
		{
			name:     "empty data is omitted",
			envelope: problem.Problem{Type: "t", Title: "T", Status: 401, Recoverable: true, Data: map[string]any{}},
			want:     `{"recoverable":true,"status":401,"title":"T","type":"t"}`,
		},
		{
			name:     "empty detail and instance are present",
			envelope: problem.Problem{Type: "t", Title: "T", Status: 400, Detail: &empty, Instance: &empty},
			want:     `{"detail":"","instance":"","recoverable":false,"status":400,"title":"T","type":"t"}`,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			envelope := tc.envelope

			// Act
			got, err := json.Marshal(envelope)

			// Assert
			if err != nil || string(got) != tc.want {
				t.Fatalf("Marshal = %s, %v; want %s", got, err, tc.want)
			}
		})
	}
}

func TestProblemMarshalJSONRejectsUnencodableData(t *testing.T) {
	t.Parallel()
	// Arrange
	envelope := problem.Problem{Type: "t", Data: map[string]any{"bad": make(chan int)}}

	// Act
	_, err := envelope.MarshalJSON()

	// Assert
	if err == nil {
		t.Fatal("expected an encoding error")
	}
}

func TestProblemUnmarshalJSON(t *testing.T) {
	t.Parallel()
	detail, instance := "d", "/i"
	cases := []struct {
		name  string
		input string
		want  problem.Problem
	}{
		{
			name:  "every member",
			input: `{"type":"t","title":"T","status":404,"detail":"d","instance":"/i","recoverable":true,"data":{"id":"42"}}`,
			want:  problem.Problem{Type: "t", Title: "T", Status: 404, Detail: &detail, Instance: &instance, Recoverable: true, Data: map[string]any{"id": "42"}},
		},
		{
			name:  "absent members take defaults",
			input: `{}`,
			want:  problem.Problem{Type: "about:blank", Title: "Unexpected problem", Status: 500},
		},
		{
			name:  "null data stays absent",
			input: `{"type":"t","title":"T","status":401,"data":null}`,
			want:  problem.Problem{Type: "t", Title: "T", Status: 401},
		},
		{
			name:  "wrong member types take defaults",
			input: `{"type":1,"title":2,"status":"x","detail":3,"instance":4,"recoverable":"yes","data":[]}`,
			want:  problem.Problem{Type: "about:blank", Title: "Unexpected problem", Status: 500},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			var got problem.Problem

			// Act
			err := json.Unmarshal([]byte(tc.input), &got)

			// Assert
			if err != nil || !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("Unmarshal = %+v, %v; want %+v", got, err, tc.want)
			}
		})
	}
}

func TestProblemUnmarshalJSONRejects(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name  string
		input string
	}{
		{name: "invalid json", input: `{`},
		{name: "null", input: `null`},
		{name: "array", input: `[]`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			var got problem.Problem

			// Act
			err := got.UnmarshalJSON([]byte(tc.input))

			// Assert
			if err == nil {
				t.Fatalf("expected an error for %s", tc.input)
			}
		})
	}
}

func TestProblemEqual(t *testing.T) {
	t.Parallel()
	base := problem.Problem{Type: "t", Title: "T", Status: 404, Data: map[string]any{"count": 1}}
	cases := []struct {
		name  string
		other problem.Problem
		want  bool
	}{
		{name: "same value", other: base, want: true},
		{name: "decoded numbers", other: problem.Problem{Type: "t", Title: "T", Status: 404, Data: map[string]any{"count": float64(1)}}, want: true},
		{name: "different status", other: problem.Problem{Type: "t", Title: "T", Status: 409, Data: base.Data}, want: false},
		{name: "unencodable", other: problem.Problem{Data: map[string]any{"bad": make(chan int)}}, want: false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Arrange
			other := tc.other

			// Act
			got := base.Equal(other)

			// Assert
			if got != tc.want {
				t.Fatalf("Equal = %t, want %t", got, tc.want)
			}
		})
	}
}

func TestProblemString(t *testing.T) {
	t.Parallel()
	// Arrange
	envelope := problem.Problem{Type: "https://x/v1/conflict", Title: "Conflict", Status: 409}

	// Act
	got := envelope.String()

	// Assert
	if got != "Problem(https://x/v1/conflict, 409, Conflict)" {
		t.Fatalf("String = %q", got)
	}
}
