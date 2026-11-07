package testhelper_test

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/ProtoDurian/diene.go-interfaces/lib/interfaces"
	"github.com/ProtoDurian/diene.go-interfaces/testhelper"
)

func Example() {
	// Arrange
	terminal := testhelper.NewInMemoryTerminal()
	cause := errors.New("launch failed")
	terminal.EnqueueResult(interfaces.TerminalOutput{}, cause)

	// Act
	_, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false))

	// Assert
	var problemErr *problem.Error
	fmt.Println(errors.As(err, &problemErr), errors.Is(err, cause))
	// Output: true true
}

func ExampleInMemorySystemOptions() {
	// Arrange
	options := testhelper.InMemorySystemOptions{}

	// Act
	system := testhelper.NewInMemorySystem(options)
	directory, _ := system.CurrentDirectory()
	now, _ := system.NowUTC()

	// Assert
	fmt.Println(directory, now.Unix())
	// Output: / 0
}

func ExampleInMemorySystem() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{Environment: map[string]string{"HOME": "/home/a"}})

	// Act
	home, _ := system.Environment("HOME")

	// Assert
	fmt.Println(*home)
	// Output: /home/a
}

func ExampleNewInMemorySystem() {
	// Arrange
	options := testhelper.InMemorySystemOptions{Directory: "/work", Now: time.Unix(60, 0)}

	// Act
	system := testhelper.NewInMemorySystem(options)

	// Assert
	directory, _ := system.CurrentDirectory()
	now, _ := system.NowUTC()
	fmt.Println(directory, now.Unix())
	// Output: /work 60
}

func ExampleInMemorySystem_EnqueueEnvironmentResult() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	system.EnqueueEnvironmentResult(nil, errors.New("denied"))

	// Act
	_, err := system.Environment("HOME")

	// Assert
	fmt.Println(err != nil)
	// Output: true
}

func ExampleInMemorySystem_EnqueueDirectoryResult() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	system.EnqueueDirectoryResult("/scripted", nil)

	// Act
	first, _ := system.CurrentDirectory()
	second, _ := system.CurrentDirectory()

	// Assert
	fmt.Println(first, second)
	// Output: /scripted /
}

func ExampleInMemorySystem_EnqueueClockResult() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	system.EnqueueClockResult(time.Unix(30, 0), nil)

	// Act
	now, _ := system.NowUTC()

	// Assert
	fmt.Println(now.Unix())
	// Output: 30
}

func ExampleInMemorySystem_EnqueueDelayResult() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	system.EnqueueDelayResult(errors.New("cancelled"))

	// Act
	err := system.Delay(context.Background(), time.Second)

	// Assert
	fmt.Println(err != nil)
	// Output: true
}

func ExampleInMemorySystem_Environment() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})

	// Act
	value, err := system.Environment("UNSET")

	// Assert
	fmt.Println(value == nil, err == nil)
	// Output: true true
}

func ExampleInMemorySystem_CurrentDirectory() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{Directory: "/repo"})

	// Act
	directory, _ := system.CurrentDirectory()

	// Assert
	fmt.Println(directory)
	// Output: /repo
}

func ExampleInMemorySystem_NowUTC() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{Now: time.Date(2026, 1, 1, 1, 0, 0, 0, time.FixedZone("plus1", 3600))})

	// Act
	now, _ := system.NowUTC()

	// Assert
	fmt.Println(now.Format(time.RFC3339))
	// Output: 2026-01-01T00:00:00Z
}

func ExampleInMemorySystem_Delay() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})

	// Act
	err := system.Delay(context.Background(), time.Hour)

	// Assert
	fmt.Println(err == nil, system.RequestedDelays())
	// Output: true [1h0m0s]
}

func ExampleInMemorySystem_RequestedDelays() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	_ = system.Delay(context.Background(), time.Second)
	_ = system.Delay(context.Background(), 2*time.Second)

	// Act
	delays := system.RequestedDelays()

	// Assert
	fmt.Println(delays)
	// Output: [1s 2s]
}

func ExampleInMemorySystem_SetEnvironment() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})

	// Act
	system.SetEnvironment("MODE", "test")

	// Assert
	mode, _ := system.Environment("MODE")
	fmt.Println(*mode)
	// Output: test
}

func ExampleInMemorySystem_SetDirectory() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})

	// Act
	system.SetDirectory("/elsewhere")

	// Assert
	directory, _ := system.CurrentDirectory()
	fmt.Println(directory)
	// Output: /elsewhere
}

func ExampleInMemorySystem_SetNow() {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})

	// Act
	system.SetNow(time.Unix(90, 0))

	// Assert
	now, _ := system.NowUTC()
	fmt.Println(now.Unix())
	// Output: 90
}

func ExampleInMemoryVfsOptions() {
	// Arrange
	options := testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/a.txt": []byte("a")}, Directories: []string{"/docs"}}

	// Act
	vfs := testhelper.NewInMemoryVfs(options)

	// Assert
	fmt.Println(vfs.Directories(), len(vfs.Files()))
	// Output: [/ /docs] 1
}

func ExampleInMemoryVfs() {
	// Arrange
	ctx := context.Background()
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})

	// Act
	_, err := vfs.ReadText(ctx, "/missing")

	// Assert
	var problemErr *problem.Error
	fmt.Println(errors.As(err, &problemErr), problemErr.Problem.Status)
	// Output: true 404
}

func ExampleNewInMemoryVfs() {
	// Arrange
	files := map[string][]byte{"//a//b.txt": []byte("b")}

	// Act
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: files})

	// Assert
	exists, _ := vfs.Exists(context.Background(), "/a/b.txt")
	fmt.Println(exists)
	// Output: true
}

func ExampleInMemoryVfs_EnqueueExistsResult() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	vfs.EnqueueExistsResult(true, nil)

	// Act
	exists, _ := vfs.Exists(context.Background(), "/scripted")

	// Assert
	fmt.Println(exists)
	// Output: true
}

func ExampleInMemoryVfs_EnqueueReadBytesResult() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	vfs.EnqueueReadBytesResult([]byte("scripted"), nil)

	// Act
	bytes, _ := vfs.ReadBytes(context.Background(), "/any")

	// Assert
	fmt.Println(string(bytes))
	// Output: scripted
}

func ExampleInMemoryVfs_EnqueueReadTextResult() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	vfs.EnqueueReadTextResult("scripted", nil)

	// Act
	text, _ := vfs.ReadText(context.Background(), "/any")

	// Assert
	fmt.Println(text)
	// Output: scripted
}

func ExampleInMemoryVfs_EnqueueWriteBytesResult() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	vfs.EnqueueWriteBytesResult(errors.New("disk full"))

	// Act
	err := vfs.WriteBytes(context.Background(), "/a", nil, interfaces.WriteOptions{})

	// Assert
	fmt.Println(err != nil, len(vfs.Files()))
	// Output: true 0
}

func ExampleInMemoryVfs_EnqueueWriteTextResult() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	vfs.EnqueueWriteTextResult(errors.New("disk full"))

	// Act
	err := vfs.WriteText(context.Background(), "/a", "x", interfaces.WriteOptions{})

	// Assert
	fmt.Println(err != nil, len(vfs.Files()))
	// Output: true 0
}

func ExampleInMemoryVfs_EnqueueListResult() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	vfs.EnqueueListResult([]interfaces.VfsEntry{{Path: "/link", Type: interfaces.VfsEntryTypeLink}}, nil)

	// Act
	entries, _ := vfs.List(context.Background(), "/", interfaces.ListOptions{})

	// Assert
	fmt.Println(entries[0].Path, entries[0].Type)
	// Output: /link link
}

func ExampleInMemoryVfs_EnqueueCreateDirectoryResult() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	vfs.EnqueueCreateDirectoryResult(errors.New("denied"))

	// Act
	err := vfs.CreateDirectory(context.Background(), "/a", interfaces.DirectoryOptions{})

	// Assert
	fmt.Println(err != nil, vfs.Directories())
	// Output: true [/]
}

func ExampleInMemoryVfs_EnqueueDeleteResult() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/a": nil}})
	vfs.EnqueueDeleteResult(errors.New("busy"))

	// Act
	err := vfs.Delete(context.Background(), "/a", interfaces.DirectoryOptions{})

	// Assert
	fmt.Println(err != nil, len(vfs.Files()))
	// Output: true 1
}

func ExampleInMemoryVfs_Exists() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})

	// Act
	root, _ := vfs.Exists(context.Background(), "/")
	missing, _ := vfs.Exists(context.Background(), "/missing")

	// Assert
	fmt.Println(root, missing)
	// Output: true false
}

func ExampleInMemoryVfs_ReadBytes() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/a": {1, 2}}})

	// Act
	bytes, _ := vfs.ReadBytes(context.Background(), "/a")

	// Assert
	fmt.Println(len(bytes), bytes[0], bytes[1])
	// Output: 2 1 2
}

func ExampleInMemoryVfs_ReadText() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/a": []byte("text")}})

	// Act
	text, _ := vfs.ReadText(context.Background(), "/a")

	// Assert
	fmt.Println(text)
	// Output: text
}

func ExampleInMemoryVfs_WriteBytes() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})

	// Act
	err := vfs.WriteBytes(context.Background(), "/a/b", []byte{7}, interfaces.WriteOptions{CreateParents: true})

	// Assert
	fmt.Println(err == nil, vfs.Files()["/a/b"][0])
	// Output: true 7
}

func ExampleInMemoryVfs_WriteText() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})

	// Act
	err := vfs.WriteText(context.Background(), "/a.txt", "hi", interfaces.WriteOptions{})

	// Assert
	fmt.Println(err == nil, string(vfs.Files()["/a.txt"]))
	// Output: true hi
}

func ExampleInMemoryVfs_List() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/b": nil, "/a": nil}})

	// Act
	entries, _ := vfs.List(context.Background(), "/", interfaces.ListOptions{})

	// Assert
	fmt.Println(entries[0].Path, entries[1].Path)
	// Output: /a /b
}

func ExampleInMemoryVfs_CreateDirectory() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})

	// Act
	err := vfs.CreateDirectory(context.Background(), "/a/b", interfaces.DirectoryOptions{})

	// Assert
	fmt.Println(err != nil)
	// Output: true
}

func ExampleInMemoryVfs_Delete() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/d/a": nil}, Directories: []string{"/d"}})

	// Act
	err := vfs.Delete(context.Background(), "/d", interfaces.DirectoryOptions{Recursive: true})

	// Assert
	fmt.Println(err == nil, vfs.Directories())
	// Output: true [/]
}

func ExampleInMemoryVfs_Files() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/a": []byte("a")}})

	// Act
	files := vfs.Files()
	files["/a"][0] = 'z'

	// Assert
	fmt.Println(string(vfs.Files()["/a"]))
	// Output: a
}

func ExampleInMemoryVfs_Directories() {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Directories: []string{"/b", "/a"}})

	// Act
	directories := vfs.Directories()

	// Assert
	fmt.Println(directories)
	// Output: [/ /a /b]
}

func ExampleInMemoryTerminal() {
	// Arrange
	terminal := testhelper.NewInMemoryTerminal()

	// Act
	_, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand("unscripted", nil, nil, nil, false, false))

	// Assert
	var problemErr *problem.Error
	fmt.Println(errors.As(err, &problemErr), problemErr.Problem.Status)
	// Output: true 500
}

func ExampleNewInMemoryTerminal() {
	// Arrange
	terminal := testhelper.NewInMemoryTerminal()

	// Act
	commands := terminal.Commands()

	// Assert
	fmt.Println(len(commands))
	// Output: 0
}

func ExampleInMemoryTerminal_EnqueueResult() {
	// Arrange
	terminal := testhelper.NewInMemoryTerminal()
	terminal.EnqueueResult(interfaces.TerminalOutput{Stdout: "first"}, nil)
	terminal.EnqueueResult(interfaces.TerminalOutput{Stdout: "second"}, nil)
	command := interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false)

	// Act
	first, _ := terminal.Run(context.Background(), command)
	second, _ := terminal.Run(context.Background(), command)

	// Assert
	fmt.Println(first.Stdout, second.Stdout)
	// Output: first second
}

func ExampleInMemoryTerminal_Run() {
	// Arrange
	terminal := testhelper.NewInMemoryTerminal()
	terminal.EnqueueResult(interfaces.TerminalOutput{ExitCode: 3}, nil)

	// Act
	output, err := terminal.Run(context.Background(), interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false))

	// Assert
	fmt.Println(output.ExitCode, err == nil)
	// Output: 3 true
}

func ExampleInMemoryTerminal_Commands() {
	// Arrange
	terminal := testhelper.NewInMemoryTerminal()
	terminal.EnqueueResult(interfaces.TerminalOutput{}, nil)
	_, _ = terminal.Run(context.Background(), interfaces.NewTerminalCommand("git", []string{"status"}, nil, nil, false, false))

	// Act
	commands := terminal.Commands()

	// Assert
	fmt.Println(commands[0].Executable, commands[0].Args)
	// Output: git [status]
}

func ExampleInMemoryLoggerSink() {
	// Arrange
	logger := testhelper.NewInMemoryLoggerSink()
	logger.EnqueueResult(errors.New("sink down"))

	// Act
	err := logger.Emit(interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelError, "lost", nil, nil, nil))

	// Assert
	fmt.Println(err != nil, len(logger.Records()))
	// Output: true 0
}

func ExampleNewInMemoryLoggerSink() {
	// Arrange
	logger := testhelper.NewInMemoryLoggerSink()

	// Act
	records := logger.Records()

	// Assert
	fmt.Println(len(records))
	// Output: 0
}

func ExampleInMemoryLoggerSink_EnqueueResult() {
	// Arrange
	logger := testhelper.NewInMemoryLoggerSink()
	logger.EnqueueResult(nil)

	// Act
	err := logger.Emit(interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelInfo, "kept", nil, nil, nil))

	// Assert
	fmt.Println(err == nil, len(logger.Records()))
	// Output: true 0
}

func ExampleInMemoryLoggerSink_Emit() {
	// Arrange
	logger := testhelper.NewInMemoryLoggerSink()

	// Act
	err := logger.Emit(interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelInfo, "ready", nil, nil, nil))

	// Assert
	fmt.Println(err == nil, logger.Records()[0].Message)
	// Output: true ready
}

func ExampleInMemoryLoggerSink_Records() {
	// Arrange
	logger := testhelper.NewInMemoryLoggerSink()
	_ = logger.Emit(interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelInfo, "a", nil, nil, nil))
	_ = logger.Emit(interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelWarning, "b", nil, nil, nil))

	// Act
	records := logger.Records()

	// Assert
	fmt.Println(records[0].Level, records[1].Level)
	// Output: info warning
}

func ExampleInMemoryMetricsCollector() {
	// Arrange
	metrics := testhelper.NewInMemoryMetricsCollector()
	metrics.EnqueueResult(errors.New("collector down"))

	// Act
	err := metrics.Emit(interfaces.NewMetricRecord(time.Unix(0, 0), "lost", interfaces.MetricKindCounter, 1, nil, nil))

	// Assert
	fmt.Println(err != nil, len(metrics.Records()))
	// Output: true 0
}

func ExampleNewInMemoryMetricsCollector() {
	// Arrange
	metrics := testhelper.NewInMemoryMetricsCollector()

	// Act
	records := metrics.Records()

	// Assert
	fmt.Println(len(records))
	// Output: 0
}

func ExampleInMemoryMetricsCollector_EnqueueResult() {
	// Arrange
	metrics := testhelper.NewInMemoryMetricsCollector()
	metrics.EnqueueResult(nil)

	// Act
	err := metrics.Emit(interfaces.NewMetricRecord(time.Unix(0, 0), "count", interfaces.MetricKindCounter, 1, nil, nil))

	// Assert
	fmt.Println(err == nil, len(metrics.Records()))
	// Output: true 0
}

func ExampleInMemoryMetricsCollector_Emit() {
	// Arrange
	metrics := testhelper.NewInMemoryMetricsCollector()

	// Act
	err := metrics.Emit(interfaces.NewMetricRecord(time.Unix(0, 0), "count", interfaces.MetricKindCounter, 1, nil, nil))

	// Assert
	fmt.Println(err == nil, metrics.Records()[0].Name)
	// Output: true count
}

func ExampleInMemoryMetricsCollector_Records() {
	// Arrange
	metrics := testhelper.NewInMemoryMetricsCollector()
	_ = metrics.Emit(interfaces.NewMetricRecord(time.Unix(0, 0), "a", interfaces.MetricKindGauge, 2, nil, nil))

	// Act
	records := metrics.Records()

	// Assert
	fmt.Println(records[0].Name, records[0].Kind, records[0].Value)
	// Output: a gauge 2
}
