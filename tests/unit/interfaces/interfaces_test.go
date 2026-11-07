package interfaces_test

import (
	"testing"
	"time"

	"github.com/ProtoDurian/diene.go-interfaces/lib/interfaces"
)

var offset = time.FixedZone("offset", 3600)

func TestNewVfsEntry(t *testing.T) {
	// Arrange
	modified := time.Date(2026, 7, 22, 1, 2, 3, 0, offset)
	cases := []struct {
		name     string
		modified *time.Time
		wantTime bool
	}{
		{"with modification time", &modified, true},
		{"without modification time", nil, false},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			// Act
			entry := interfaces.NewVfsEntry("/a", interfaces.VfsEntryTypeFile, 4, testCase.modified)

			// Assert
			if entry.Path != "/a" || entry.Type != interfaces.VfsEntryTypeFile || entry.Size != 4 || (entry.ModifiedAt != nil) != testCase.wantTime {
				t.Fatalf("unexpected entry: %#v", entry)
			}
			if testCase.wantTime && (entry.ModifiedAt.Location() != time.UTC || !entry.ModifiedAt.Equal(modified) || entry.ModifiedAt == testCase.modified) {
				t.Fatalf("modification time must be a UTC copy: %#v", entry.ModifiedAt)
			}
		})
	}
}

func TestWireNames(t *testing.T) {
	// Arrange
	cases := []struct {
		got  func() string
		want string
	}{
		{interfaces.VfsEntryTypeFile.String, "file"},
		{interfaces.VfsEntryTypeDirectory.String, "directory"},
		{interfaces.VfsEntryTypeLink.String, "link"},
		{interfaces.LogLevelTrace.String, "trace"},
		{interfaces.LogLevelDebug.String, "debug"},
		{interfaces.LogLevelInfo.String, "info"},
		{interfaces.LogLevelWarning.String, "warning"},
		{interfaces.LogLevelError.String, "error"},
		{interfaces.LogLevelFatal.String, "fatal"},
		{interfaces.MetricKindCounter.String, "counter"},
		{interfaces.MetricKindGauge.String, "gauge"},
		{interfaces.MetricKindHistogram.String, "histogram"},
	}
	for _, testCase := range cases {
		t.Run(testCase.want, func(t *testing.T) {
			// Act
			got := testCase.got()

			// Assert
			if got != testCase.want {
				t.Fatalf("got %q, want %q", got, testCase.want)
			}
		})
	}
}

func TestNewTerminalCommandClonesInputs(t *testing.T) {
	// Arrange
	directory := "/tmp"
	args := []string{"one"}
	environment := map[string]string{"A": "1"}

	// Act
	command := interfaces.NewTerminalCommand("tool", args, &directory, environment, true, true)
	args[0], environment["A"], directory = "two", "2", "/other"

	// Assert
	if command.Executable != "tool" || command.Args[0] != "one" || command.Environment["A"] != "1" || *command.WorkingDirectory != "/tmp" || !command.IncludeParentEnvironment || !command.RunInShell {
		t.Fatalf("constructor did not clone: %#v", command)
	}
}

func TestNewTerminalCommandWithoutOptionalInputs(t *testing.T) {
	// Arrange
	var args []string

	// Act
	command := interfaces.NewTerminalCommand("tool", args, nil, nil, false, false)

	// Assert
	if command.WorkingDirectory != nil || len(command.Args) != 0 || command.Environment == nil || len(command.Environment) != 0 {
		t.Fatalf("unexpected optional command fields: %#v", command)
	}
}

func TestTerminalCommandClone(t *testing.T) {
	// Arrange
	directory := "/tmp"
	command := interfaces.NewTerminalCommand("tool", []string{"one"}, &directory, map[string]string{"A": "1"}, true, false)

	// Act
	clone := command.Clone()
	clone.Args[0], clone.Environment["A"], *clone.WorkingDirectory = "changed", "changed", "/changed"

	// Assert
	if command.Args[0] != "one" || command.Environment["A"] != "1" || *command.WorkingDirectory != "/tmp" {
		t.Fatalf("clone aliases command: %#v", command)
	}
}

func TestTerminalOutputSucceeded(t *testing.T) {
	// Arrange
	cases := map[int]bool{0: true, 1: false, -1: false}
	for code, want := range cases {
		// Act
		got := interfaces.TerminalOutput{ExitCode: code}.Succeeded()

		// Assert
		if got != want {
			t.Fatalf("exit %d: got %v, want %v", code, got, want)
		}
	}
}

func TestNewLogRecordCopiesInputs(t *testing.T) {
	// Arrange
	message, stack := "failure", "stack"
	attributes := map[string]any{"attempt": 1}

	// Act
	record := interfaces.NewLogRecord(time.Date(2026, 7, 22, 1, 2, 3, 0, offset), interfaces.LogLevelWarning, "retry", attributes, &message, &stack)
	attributes["attempt"], message, stack = 2, "changed", "changed"

	// Assert
	if record.Timestamp.Location() != time.UTC || record.Level != interfaces.LogLevelWarning || record.Message != "retry" || record.Attributes["attempt"] != 1 || *record.Error != "failure" || *record.StackTrace != "stack" {
		t.Fatalf("record was not copied: %#v", record)
	}
}

func TestNewLogRecordWithoutOptionalInputs(t *testing.T) {
	// Arrange
	var attributes map[string]any

	// Act
	record := interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelInfo, "m", attributes, nil, nil)

	// Assert
	if record.Error != nil || record.StackTrace != nil || record.Attributes == nil {
		t.Fatalf("unexpected optional fields: %#v", record)
	}
}

func TestLogRecordClone(t *testing.T) {
	// Arrange
	message := "failure"
	record := interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelError, "m", map[string]any{"attempt": 1}, &message, nil)

	// Act
	clone := record.Clone()
	clone.Attributes["attempt"], *clone.Error = 3, "changed"

	// Assert
	if record.Attributes["attempt"] != 1 || *record.Error != "failure" {
		t.Fatalf("clone aliases record: %#v", record)
	}
}

func TestCloneAttributes(t *testing.T) {
	// Arrange
	source := map[string]any{"key": "value"}

	// Act
	fromNil := interfaces.CloneAttributes(nil)
	copied := interfaces.CloneAttributes(source)
	copied["key"] = "changed"

	// Assert
	if fromNil == nil || len(fromNil) != 0 || source["key"] != "value" {
		t.Fatalf("CloneAttributes: %#v %#v", fromNil, source)
	}
}

func TestNewMetricRecordCopiesInputs(t *testing.T) {
	// Arrange
	unit := "ms"
	attributes := map[string]any{"route": "/"}

	// Act
	record := interfaces.NewMetricRecord(time.Date(2026, 7, 22, 1, 2, 3, 0, offset), "latency", interfaces.MetricKindHistogram, 2.5, &unit, attributes)
	unit, attributes["route"] = "s", "/changed"

	// Assert
	if record.Timestamp.Location() != time.UTC || record.Name != "latency" || record.Kind != interfaces.MetricKindHistogram || record.Value != 2.5 || *record.Unit != "ms" || record.Attributes["route"] != "/" {
		t.Fatalf("metric was not copied: %#v", record)
	}
}

func TestMetricRecordClone(t *testing.T) {
	// Arrange
	record := interfaces.NewMetricRecord(time.Unix(0, 0), "count", interfaces.MetricKindCounter, 1, nil, map[string]any{"route": "/"})

	// Act
	clone := record.Clone()
	clone.Attributes["route"] = "/clone"

	// Assert
	if record.Attributes["route"] != "/" || clone.Unit != nil {
		t.Fatalf("clone aliases metric: %#v", record)
	}
}
