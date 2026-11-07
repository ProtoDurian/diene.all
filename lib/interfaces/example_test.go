package interfaces_test

import (
	"context"
	"fmt"
	"time"

	"github.com/ProtoDurian/diene.go-interfaces/lib/interfaces"
	"github.com/ProtoDurian/diene.go-interfaces/testhelper"
)

func ExampleSystem() {
	// Arrange
	var system interfaces.System = testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{Environment: map[string]string{"EMPTY": ""}})

	// Act
	empty, _ := system.Environment("EMPTY")
	unset, _ := system.Environment("UNSET")

	// Assert
	fmt.Println(empty != nil, unset == nil)
	// Output: true true
}

func ExampleVfs() {
	// Arrange
	ctx := context.Background()
	var vfs interfaces.Vfs = testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})

	// Act
	_ = vfs.WriteText(ctx, "/docs/a.txt", "hi", interfaces.WriteOptions{CreateParents: true})
	text, _ := vfs.ReadText(ctx, "/docs/a.txt")

	// Assert
	fmt.Println(text)
	// Output: hi
}

func ExampleVfsEntryType() {
	// Arrange
	types := []interfaces.VfsEntryType{interfaces.VfsEntryTypeFile, interfaces.VfsEntryTypeDirectory, interfaces.VfsEntryTypeLink}

	// Act
	names := make([]string, len(types))
	for index, entryType := range types {
		names[index] = string(entryType)
	}

	// Assert
	fmt.Println(names)
	// Output: [file directory link]
}

func ExampleVfsEntryType_String() {
	// Arrange
	entryType := interfaces.VfsEntryTypeDirectory

	// Act
	name := entryType.String()

	// Assert
	fmt.Println(name)
	// Output: directory
}

func ExampleVfsEntry() {
	// Arrange
	entry := interfaces.VfsEntry{Path: "/a", Type: interfaces.VfsEntryTypeFile, Size: 3}

	// Act
	hasTime := entry.ModifiedAt != nil

	// Assert
	fmt.Println(entry.Path, entry.Type, entry.Size, hasTime)
	// Output: /a file 3 false
}

func ExampleNewVfsEntry() {
	// Arrange
	modified := time.Date(2026, 1, 1, 9, 0, 0, 0, time.FixedZone("plus1", 3600))

	// Act
	entry := interfaces.NewVfsEntry("/a", interfaces.VfsEntryTypeFile, 3, &modified)

	// Assert
	fmt.Println(entry.ModifiedAt.Format(time.RFC3339))
	// Output: 2026-01-01T08:00:00Z
}

func ExampleWriteOptions() {
	// Arrange
	ctx := context.Background()
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})

	// Act
	err := vfs.WriteText(ctx, "/missing/a.txt", "x", interfaces.WriteOptions{CreateParents: false})

	// Assert
	fmt.Println(err != nil)
	// Output: true
}

func ExampleVfsWriteOptions() {
	// Arrange
	options := interfaces.VfsWriteOptions{CreateParents: true}

	// Act
	same := options == interfaces.WriteOptions{CreateParents: true}

	// Assert
	fmt.Println(same)
	// Output: true
}

func ExampleListOptions() {
	// Arrange
	ctx := context.Background()
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/a/b/c": nil}, Directories: []string{"/a", "/a/b"}})

	// Act
	direct, _ := vfs.List(ctx, "/a", interfaces.ListOptions{})
	all, _ := vfs.List(ctx, "/a", interfaces.ListOptions{Recursive: true})

	// Assert
	fmt.Println(len(direct), len(all))
	// Output: 1 2
}

func ExampleVfsListOptions() {
	// Arrange
	options := interfaces.VfsListOptions{Recursive: true}

	// Act
	same := options == interfaces.ListOptions{Recursive: true}

	// Assert
	fmt.Println(same)
	// Output: true
}

func ExampleDirectoryOptions() {
	// Arrange
	ctx := context.Background()
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})

	// Act
	err := vfs.CreateDirectory(ctx, "/a/b", interfaces.DirectoryOptions{Recursive: true})
	exists, _ := vfs.Exists(ctx, "/a")

	// Assert
	fmt.Println(err == nil, exists)
	// Output: true true
}

func ExampleVfsDirectoryOptions() {
	// Arrange
	options := interfaces.VfsDirectoryOptions{Recursive: true}

	// Act
	same := options == interfaces.DirectoryOptions{Recursive: true}

	// Assert
	fmt.Println(same)
	// Output: true
}

func ExampleTerminal() {
	// Arrange
	terminal := testhelper.NewInMemoryTerminal()
	terminal.EnqueueResult(interfaces.TerminalOutput{ExitCode: 1, Stderr: "usage"}, nil)
	var port interfaces.Terminal = terminal

	// Act
	output, err := port.Run(context.Background(), interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false))

	// Assert
	fmt.Println(output.ExitCode, err == nil)
	// Output: 1 true
}

func ExampleTerminalCommand() {
	// Arrange
	command := interfaces.TerminalCommand{Executable: "echo", Args: []string{"hi"}}

	// Act
	args := len(command.Args)

	// Assert
	fmt.Println(command.Executable, args)
	// Output: echo 1
}

func ExampleNewTerminalCommand() {
	// Arrange
	args := []string{"hello"}

	// Act
	command := interfaces.NewTerminalCommand("echo", args, nil, nil, true, false)
	args[0] = "changed"

	// Assert
	fmt.Println(command.Executable, command.Args[0])
	// Output: echo hello
}

func ExampleTerminalCommand_Clone() {
	// Arrange
	command := interfaces.NewTerminalCommand("echo", []string{"hello"}, nil, nil, true, false)

	// Act
	clone := command.Clone()
	clone.Args[0] = "changed"

	// Assert
	fmt.Println(command.Args[0])
	// Output: hello
}

func ExampleTerminalOutput() {
	// Arrange
	output := interfaces.TerminalOutput{ExitCode: 0, Stdout: "ok"}

	// Act
	stdout := output.Stdout

	// Assert
	fmt.Println(output.ExitCode, stdout)
	// Output: 0 ok
}

func ExampleTerminalOutput_Succeeded() {
	// Arrange
	output := interfaces.TerminalOutput{ExitCode: 2, Stderr: "usage"}

	// Act
	succeeded := output.Succeeded()

	// Assert
	fmt.Println(succeeded)
	// Output: false
}

func ExampleLogLevel() {
	// Arrange
	levels := []interfaces.LogLevel{interfaces.LogLevelTrace, interfaces.LogLevelDebug, interfaces.LogLevelInfo, interfaces.LogLevelWarning, interfaces.LogLevelError, interfaces.LogLevelFatal}

	// Act
	names := make([]string, len(levels))
	for index, level := range levels {
		names[index] = string(level)
	}

	// Assert
	fmt.Println(names)
	// Output: [trace debug info warning error fatal]
}

func ExampleLogLevel_String() {
	// Arrange
	level := interfaces.LogLevelWarning

	// Act
	name := level.String()

	// Assert
	fmt.Println(name)
	// Output: warning
}

func ExampleLogRecord() {
	// Arrange
	record := interfaces.LogRecord{Level: interfaces.LogLevelInfo, Message: "ready"}

	// Act
	hasError := record.Error != nil

	// Assert
	fmt.Println(record.Level, record.Message, hasError)
	// Output: info ready false
}

func ExampleNewLogRecord() {
	// Arrange
	attributes := map[string]any{"attempt": 1}

	// Act
	record := interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelInfo, "ready", attributes, nil, nil)
	attributes["attempt"] = 2

	// Assert
	fmt.Println(record.Attributes["attempt"], record.Timestamp.Location())
	// Output: 1 UTC
}

func ExampleLogRecord_Clone() {
	// Arrange
	record := interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelInfo, "ready", map[string]any{"attempt": 1}, nil, nil)

	// Act
	clone := record.Clone()
	clone.Attributes["attempt"] = 2

	// Assert
	fmt.Println(record.Attributes["attempt"])
	// Output: 1
}

func ExampleCloneAttributes() {
	// Arrange
	var attributes map[string]any

	// Act
	cloned := interfaces.CloneAttributes(attributes)

	// Assert
	fmt.Println(cloned != nil, len(cloned))
	// Output: true 0
}

func ExampleLoggerSink() {
	// Arrange
	logger := testhelper.NewInMemoryLoggerSink()
	var sink interfaces.LoggerSink = logger

	// Act
	err := sink.Emit(interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelInfo, "ready", nil, nil, nil))

	// Assert
	fmt.Println(err == nil, len(logger.Records()))
	// Output: true 1
}

func ExampleMetricKind() {
	// Arrange
	kinds := []interfaces.MetricKind{interfaces.MetricKindCounter, interfaces.MetricKindGauge, interfaces.MetricKindHistogram}

	// Act
	names := make([]string, len(kinds))
	for index, kind := range kinds {
		names[index] = string(kind)
	}

	// Assert
	fmt.Println(names)
	// Output: [counter gauge histogram]
}

func ExampleMetricKind_String() {
	// Arrange
	kind := interfaces.MetricKindGauge

	// Act
	name := kind.String()

	// Assert
	fmt.Println(name)
	// Output: gauge
}

func ExampleMetricRecord() {
	// Arrange
	record := interfaces.MetricRecord{Name: "latency", Kind: interfaces.MetricKindHistogram, Value: 2.5}

	// Act
	hasUnit := record.Unit != nil

	// Assert
	fmt.Println(record.Name, record.Kind, record.Value, hasUnit)
	// Output: latency histogram 2.5 false
}

func ExampleNewMetricRecord() {
	// Arrange
	unit := "ms"

	// Act
	record := interfaces.NewMetricRecord(time.Unix(0, 0), "latency", interfaces.MetricKindHistogram, 2.5, &unit, nil)
	unit = "s"

	// Assert
	fmt.Println(*record.Unit, len(record.Attributes))
	// Output: ms 0
}

func ExampleMetricRecord_Clone() {
	// Arrange
	record := interfaces.NewMetricRecord(time.Unix(0, 0), "count", interfaces.MetricKindCounter, 1, nil, map[string]any{"route": "/"})

	// Act
	clone := record.Clone()
	clone.Attributes["route"] = "/other"

	// Assert
	fmt.Println(record.Attributes["route"])
	// Output: /
}

func ExampleMetricsCollector() {
	// Arrange
	metrics := testhelper.NewInMemoryMetricsCollector()
	var collector interfaces.MetricsCollector = metrics

	// Act
	err := collector.Emit(interfaces.NewMetricRecord(time.Unix(0, 0), "count", interfaces.MetricKindCounter, 1, nil, nil))

	// Assert
	fmt.Println(err == nil, len(metrics.Records()))
	// Output: true 1
}
