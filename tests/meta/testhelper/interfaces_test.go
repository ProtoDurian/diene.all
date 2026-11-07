package testhelper_test

import (
	"context"
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	probtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
	"github.com/ProtoDurian/diene.go-interfaces/lib/interfaces"
	"github.com/ProtoDurian/diene.go-interfaces/testhelper"
)

const canonicalTypePrefix = "https://docs.diene.atomicloud.com/docs/diene/go/interfaces/testhelper/v1/"

var errInjected = errors.New("injected")

func assertFault(t *testing.T, err error, id string, status int) {
	t.Helper()
	probtest.AssertError(
		t, err,
		probtest.ExpectType(canonicalTypePrefix+id),
		probtest.ExpectID(id),
		probtest.ExpectStatus(status),
		probtest.ExpectData(map[string]any{"id": id}),
	)
}

func TestInMemorySystemDefaults(t *testing.T) {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})

	// Act
	directory, directoryErr := system.CurrentDirectory()
	now, nowErr := system.NowUTC()

	// Assert
	if directory != "/" || directoryErr != nil || !now.Equal(time.Unix(0, 0)) || now.Location() != time.UTC || nowErr != nil {
		t.Fatalf("defaults: %q %v %v %v", directory, directoryErr, now, nowErr)
	}
}

func TestInMemorySystemState(t *testing.T) {
	// Arrange
	environment := map[string]string{"present": "value"}
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{Environment: environment, Directory: "/work", Now: time.Date(2026, 7, 22, 2, 3, 4, 0, time.FixedZone("offset", 3600))})
	environment["present"] = "mutated"

	// Act
	present, _ := system.Environment("present")
	missing, missingErr := system.Environment("missing")
	directory, _ := system.CurrentDirectory()
	now, _ := system.NowUTC()
	system.SetEnvironment("new", "yes")
	system.SetDirectory("/other")
	system.SetNow(time.Unix(5, 0))
	added, _ := system.Environment("new")
	changedDirectory, _ := system.CurrentDirectory()
	changedNow, _ := system.NowUTC()

	// Assert
	if *present != "value" || missing != nil || missingErr != nil || directory != "/work" || now.Location() != time.UTC || now.Hour() != 1 {
		t.Fatalf("seeded state: %v %v %v %q %v", *present, missing, missingErr, directory, now)
	}
	if *added != "yes" || changedDirectory != "/other" || changedNow.Unix() != 5 {
		t.Fatalf("set state: %v %q %v", *added, changedDirectory, changedNow)
	}
}

func TestInMemorySystemScriptedResults(t *testing.T) {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{Directory: "/real"})
	queued := "queued"
	system.EnqueueEnvironmentResult(&queued, errInjected)
	system.EnqueueEnvironmentResult(nil, nil)
	system.EnqueueDirectoryResult("/queued", errInjected)
	system.EnqueueClockResult(time.Date(2026, 1, 1, 0, 0, 0, 0, time.FixedZone("offset", 3600)), errInjected)
	system.EnqueueDelayResult(errInjected)
	queued = "mutated"

	// Act
	first, firstErr := system.Environment("x")
	second, secondErr := system.Environment("x")
	directory, directoryErr := system.CurrentDirectory()
	afterDirectory, _ := system.CurrentDirectory()
	now, nowErr := system.NowUTC()
	delayErr := system.Delay(context.Background(), time.Second)
	nextDelayErr := system.Delay(context.Background(), 2*time.Second)

	// Assert
	if *first != "queued" || !errors.Is(firstErr, errInjected) || second != nil || secondErr != nil {
		t.Fatalf("environment: %v %v %v %v", first, firstErr, second, secondErr)
	}
	if directory != "/queued" || !errors.Is(directoryErr, errInjected) || afterDirectory != "/real" {
		t.Fatalf("directory: %q %v %q", directory, directoryErr, afterDirectory)
	}
	if now.Location() != time.UTC || !errors.Is(nowErr, errInjected) {
		t.Fatalf("clock: %v %v", now, nowErr)
	}
	if !errors.Is(delayErr, errInjected) || nextDelayErr != nil || !slices.Equal(system.RequestedDelays(), []time.Duration{time.Second, 2 * time.Second}) {
		t.Fatalf("delay: %v %v %v", delayErr, nextDelayErr, system.RequestedDelays())
	}
}

func TestInMemorySystemDelayHonoursContext(t *testing.T) {
	// Arrange
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	system.EnqueueDelayResult(nil)

	// Act
	scriptedErr := system.Delay(cancelled, time.Second)
	cancelledErr := system.Delay(cancelled, 2*time.Second)
	liveErr := system.Delay(context.Background(), 3*time.Second)

	// Assert
	if scriptedErr != nil || liveErr != nil {
		t.Fatalf("scripted or live delay failed: %v %v", scriptedErr, liveErr)
	}
	var problemErr *problem.Error
	if !errors.As(cancelledErr, &problemErr) || !errors.Is(cancelledErr, context.Canceled) {
		t.Fatalf("cancelled delay: %v", cancelledErr)
	}
	if !slices.Equal(system.RequestedDelays(), []time.Duration{time.Second, 2 * time.Second, 3 * time.Second}) {
		t.Fatalf("delays: %v", system.RequestedDelays())
	}
}

func TestInMemorySystemSnapshotsAreIndependent(t *testing.T) {
	// Arrange
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	_ = system.Delay(context.Background(), time.Second)

	// Act
	delays := system.RequestedDelays()
	delays[0] = 0

	// Assert
	if system.RequestedDelays()[0] != time.Second {
		t.Fatal("delays alias state")
	}
}

func TestInMemoryVfsFaults(t *testing.T) {
	// Arrange
	ctx := context.Background()
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/a/file": []byte("t")}, Directories: []string{"/a", "/parent", "/parent/child"}})
	cases := []struct {
		name   string
		run    func() error
		id     string
		status int
	}{
		{"read bytes missing", func() error { _, err := vfs.ReadBytes(ctx, "/missing"); return err }, "path-not-found", 404},
		{"read text missing", func() error { _, err := vfs.ReadText(ctx, "/missing"); return err }, "path-not-found", 404},
		{"write bytes without parent", func() error { return vfs.WriteBytes(ctx, "/no/file", nil, interfaces.WriteOptions{}) }, "path-not-found", 404},
		{"write text without parent", func() error { return vfs.WriteText(ctx, "/no/file", "", interfaces.WriteOptions{}) }, "path-not-found", 404},
		{"list missing", func() error { _, err := vfs.List(ctx, "/missing", interfaces.ListOptions{}); return err }, "path-not-found", 404},
		{"mkdir without parent", func() error { return vfs.CreateDirectory(ctx, "/none/child", interfaces.DirectoryOptions{}) }, "path-not-found", 404},
		{"delete missing", func() error { return vfs.Delete(ctx, "/missing", interfaces.DirectoryOptions{}) }, "path-not-found", 404},
		{"delete dir holding a file", func() error { return vfs.Delete(ctx, "/a", interfaces.DirectoryOptions{}) }, "directory-not-empty", 409},
		{"delete dir holding a dir", func() error { return vfs.Delete(ctx, "/parent", interfaces.DirectoryOptions{}) }, "directory-not-empty", 409},
		{"write bytes onto a directory", func() error { return vfs.WriteBytes(ctx, "/a", nil, interfaces.WriteOptions{}) }, "path-is-directory", 409},
		{"write text onto a directory", func() error { return vfs.WriteText(ctx, "/a", "", interfaces.WriteOptions{}) }, "path-is-directory", 409},
		{"write under a file", func() error { return vfs.WriteText(ctx, "/a/file/x", "", interfaces.WriteOptions{CreateParents: true}) }, "not-a-directory", 409},
		{"mkdir onto a file", func() error { return vfs.CreateDirectory(ctx, "/a/file", interfaces.DirectoryOptions{}) }, "path-is-file", 409},
		{"mkdir under a file", func() error {
			return vfs.CreateDirectory(ctx, "/a/file/x", interfaces.DirectoryOptions{Recursive: true})
		}, "not-a-directory", 409},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			// Act
			err := testCase.run()

			// Assert
			assertFault(t, err, testCase.id, testCase.status)
		})
	}
}

func TestInMemoryVfsState(t *testing.T) {
	// Arrange
	ctx := context.Background()
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"//a//file": []byte("text")}, Directories: []string{"/a", "/a/sub"}})

	// Act
	exists, _ := vfs.Exists(ctx, "/a/file")
	bytes, _ := vfs.ReadBytes(ctx, "/a/file")
	bytes[0] = 'x'
	text, _ := vfs.ReadText(ctx, "/a/file")
	writeErr := vfs.WriteBytes(ctx, "/new/file", []byte("bytes"), interfaces.WriteOptions{CreateParents: true})
	textErr := vfs.WriteText(ctx, "/new/text", "hello", interfaces.WriteOptions{})
	mkdirErrs := []error{
		vfs.CreateDirectory(ctx, "/created/a", interfaces.DirectoryOptions{Recursive: true}),
		vfs.CreateDirectory(ctx, "/top", interfaces.DirectoryOptions{}),
		vfs.CreateDirectory(ctx, "/", interfaces.DirectoryOptions{}),
	}
	direct, _ := vfs.List(ctx, "/a", interfaces.ListOptions{})
	fileDeleteErr := vfs.Delete(ctx, "/a/file", interfaces.DirectoryOptions{})
	treeDeleteErr := vfs.Delete(ctx, "/a", interfaces.DirectoryOptions{Recursive: true})

	// Assert
	if !exists || text != "text" || writeErr != nil || textErr != nil || fileDeleteErr != nil || treeDeleteErr != nil || slices.ContainsFunc(mkdirErrs, func(err error) bool { return err != nil }) {
		t.Fatalf("operations: %v %q %v %v %v %v %v", exists, text, writeErr, textErr, mkdirErrs, fileDeleteErr, treeDeleteErr)
	}
	if len(direct) != 2 || direct[0].Path != "/a/file" || direct[1].Path != "/a/sub" {
		t.Fatalf("list: %#v", direct)
	}
	if !slices.Equal(vfs.Directories(), []string{"/", "/created", "/created/a", "/new", "/top"}) || len(vfs.Files()) != 2 {
		t.Fatalf("final state: %v %v", vfs.Directories(), vfs.Files())
	}
}

func TestInMemoryVfsDeleteRootKeepsRoot(t *testing.T) {
	// Arrange
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/child/file": []byte("x")}, Directories: []string{"/child"}})

	// Act
	err := vfs.Delete(context.Background(), "/", interfaces.DirectoryOptions{Recursive: true})

	// Assert
	if err != nil || !slices.Equal(vfs.Directories(), []string{"/"}) || len(vfs.Files()) != 0 {
		t.Fatalf("delete root: %v %v %v", err, vfs.Directories(), vfs.Files())
	}
}

func TestInMemoryVfsScriptedResults(t *testing.T) {
	// Arrange
	ctx := context.Background()
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	queuedBytes := []byte("queued")
	vfs.EnqueueExistsResult(true, errInjected)
	vfs.EnqueueReadBytesResult(queuedBytes, errInjected)
	vfs.EnqueueReadTextResult("queued", errInjected)
	vfs.EnqueueWriteBytesResult(errInjected)
	vfs.EnqueueWriteTextResult(errInjected)
	queuedEntries := []interfaces.VfsEntry{{Path: "/script", Type: interfaces.VfsEntryTypeLink}}
	vfs.EnqueueListResult(queuedEntries, errInjected)
	vfs.EnqueueCreateDirectoryResult(errInjected)
	vfs.EnqueueDeleteResult(errInjected)
	queuedBytes[0], queuedEntries[0].Path = 'x', "/mutated"

	// Act
	exists, existsErr := vfs.Exists(ctx, "/no")
	bytes, bytesErr := vfs.ReadBytes(ctx, "/x")
	text, textErr := vfs.ReadText(ctx, "/x")
	writeBytesErr := vfs.WriteBytes(ctx, "/x", nil, interfaces.WriteOptions{})
	writeTextErr := vfs.WriteText(ctx, "/x", "x", interfaces.WriteOptions{})
	entries, listErr := vfs.List(ctx, "/", interfaces.ListOptions{})
	mkdirErr := vfs.CreateDirectory(ctx, "/x", interfaces.DirectoryOptions{})
	deleteErr := vfs.Delete(ctx, "/x", interfaces.DirectoryOptions{})

	// Assert
	for name, err := range map[string]error{"exists": existsErr, "bytes": bytesErr, "text": textErr, "writeBytes": writeBytesErr, "writeText": writeTextErr, "list": listErr, "mkdir": mkdirErr, "delete": deleteErr} {
		if !errors.Is(err, errInjected) {
			t.Fatalf("%s: %v", name, err)
		}
	}
	if !exists || string(bytes) != "queued" || text != "queued" || len(entries) != 1 || entries[0].Path != "/script" {
		t.Fatalf("scripted values: %v %q %q %#v", exists, bytes, text, entries)
	}
	if len(vfs.Files()) != 0 || !slices.Equal(vfs.Directories(), []string{"/"}) {
		t.Fatal("scripted results must not touch the store")
	}
}

func TestInMemoryVfsSnapshotsAreIndependent(t *testing.T) {
	// Arrange
	ctx := context.Background()
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/a": []byte("a")}, Directories: []string{"/d"}})
	vfs.EnqueueReadBytesResult([]byte("queued"), nil)
	vfs.EnqueueListResult([]interfaces.VfsEntry{{Path: "/script"}}, nil)

	// Act
	queued, _ := vfs.ReadBytes(ctx, "/a")
	entries, _ := vfs.List(ctx, "/", interfaces.ListOptions{})
	queued[0], entries[0].Path = 'x', "changed"
	files := vfs.Files()
	files["/a"][0] = 'z'
	directories := vfs.Directories()
	directories[0] = "changed"

	// Assert
	again, _ := vfs.List(ctx, "/", interfaces.ListOptions{})
	if string(vfs.Files()["/a"]) != "a" || vfs.Directories()[0] != "/" || again[0].Path != "/a" {
		t.Fatalf("snapshots alias state: %v %v %v", vfs.Files(), vfs.Directories(), again)
	}
}

func TestInMemoryTerminal(t *testing.T) {
	// Arrange
	terminal := testhelper.NewInMemoryTerminal()
	command := interfaces.NewTerminalCommand("tool", []string{"one"}, nil, map[string]string{"A": "1"}, true, false)
	terminal.EnqueueResult(interfaces.TerminalOutput{ExitCode: 2, Stderr: "no"}, errInjected)

	// Act
	output, scriptedErr := terminal.Run(context.Background(), command)
	_, unscriptedErr := terminal.Run(context.Background(), command)
	commands := terminal.Commands()
	commands[0].Args[0] = "changed"

	// Assert
	if output.ExitCode != 2 || output.Stderr != "no" || !errors.Is(scriptedErr, errInjected) {
		t.Fatalf("scripted run: %#v %v", output, scriptedErr)
	}
	assertFault(t, unscriptedErr, "terminal-result-not-scripted", 500)
	if again := terminal.Commands(); len(again) != 2 || again[0].Args[0] != "one" {
		t.Fatalf("commands alias state: %#v", again)
	}
}

func TestInMemoryLoggerSink(t *testing.T) {
	// Arrange
	logger := testhelper.NewInMemoryLoggerSink()
	record := interfaces.NewLogRecord(time.Unix(0, 0), interfaces.LogLevelInfo, "message", map[string]any{"key": "value"}, nil, nil)
	logger.EnqueueResult(errInjected)

	// Act
	failedErr := logger.Emit(record)
	failedRecords := len(logger.Records())
	okErr := logger.Emit(record)
	records := logger.Records()
	records[0].Attributes["key"] = "changed"

	// Assert
	if !errors.Is(failedErr, errInjected) || failedRecords != 0 || okErr != nil {
		t.Fatalf("emit: %v %d %v", failedErr, failedRecords, okErr)
	}
	if again := logger.Records(); len(again) != 1 || again[0].Attributes["key"] != "value" {
		t.Fatalf("records alias state: %#v", again)
	}
}

func TestInMemoryMetricsCollector(t *testing.T) {
	// Arrange
	metrics := testhelper.NewInMemoryMetricsCollector()
	record := interfaces.NewMetricRecord(time.Unix(0, 0), "count", interfaces.MetricKindCounter, 1, nil, map[string]any{"key": "value"})
	metrics.EnqueueResult(errInjected)

	// Act
	failedErr := metrics.Emit(record)
	failedRecords := len(metrics.Records())
	okErr := metrics.Emit(record)
	records := metrics.Records()
	records[0].Attributes["key"] = "changed"

	// Assert
	if !errors.Is(failedErr, errInjected) || failedRecords != 0 || okErr != nil {
		t.Fatalf("emit: %v %d %v", failedErr, failedRecords, okErr)
	}
	if again := metrics.Records(); len(again) != 1 || again[0].Attributes["key"] != "value" {
		t.Fatalf("records alias state: %#v", again)
	}
}

func TestInjectedErrorsAreProblemTyped(t *testing.T) {
	// Arrange
	ctx := context.Background()
	seams := map[string]func(injected error) error{
		"system.environment": func(injected error) error {
			s := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			s.EnqueueEnvironmentResult(nil, injected)
			_, err := s.Environment("x")
			return err
		},
		"system.directory": func(injected error) error {
			s := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			s.EnqueueDirectoryResult("", injected)
			_, err := s.CurrentDirectory()
			return err
		},
		"system.clock": func(injected error) error {
			s := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			s.EnqueueClockResult(time.Time{}, injected)
			_, err := s.NowUTC()
			return err
		},
		"system.delay": func(injected error) error {
			s := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			s.EnqueueDelayResult(injected)
			return s.Delay(ctx, time.Second)
		},
		"vfs.exists": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueExistsResult(false, injected)
			_, err := v.Exists(ctx, "/x")
			return err
		},
		"vfs.readBytes": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueReadBytesResult(nil, injected)
			_, err := v.ReadBytes(ctx, "/x")
			return err
		},
		"vfs.readText": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueReadTextResult("", injected)
			_, err := v.ReadText(ctx, "/x")
			return err
		},
		"vfs.writeBytes": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueWriteBytesResult(injected)
			return v.WriteBytes(ctx, "/x", nil, interfaces.WriteOptions{})
		},
		"vfs.writeText": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueWriteTextResult(injected)
			return v.WriteText(ctx, "/x", "", interfaces.WriteOptions{})
		},
		"vfs.list": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueListResult(nil, injected)
			_, err := v.List(ctx, "/", interfaces.ListOptions{})
			return err
		},
		"vfs.createDirectory": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueCreateDirectoryResult(injected)
			return v.CreateDirectory(ctx, "/x", interfaces.DirectoryOptions{})
		},
		"vfs.delete": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueDeleteResult(injected)
			return v.Delete(ctx, "/x", interfaces.DirectoryOptions{})
		},
		"terminal.run": func(injected error) error {
			term := testhelper.NewInMemoryTerminal()
			term.EnqueueResult(interfaces.TerminalOutput{}, injected)
			_, err := term.Run(ctx, interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false))
			return err
		},
		"logger.emit": func(injected error) error {
			logger := testhelper.NewInMemoryLoggerSink()
			logger.EnqueueResult(injected)
			return logger.Emit(interfaces.NewLogRecord(time.Now(), interfaces.LogLevelInfo, "m", nil, nil, nil))
		},
		"metrics.emit": func(injected error) error {
			metrics := testhelper.NewInMemoryMetricsCollector()
			metrics.EnqueueResult(injected)
			return metrics.Emit(interfaces.NewMetricRecord(time.Now(), "c", interfaces.MetricKindCounter, 1, nil, nil))
		},
	}
	for name, run := range seams {
		t.Run(name, func(t *testing.T) {
			injected := errors.New("injected cause")

			// Act
			err := run(injected)

			// Assert
			var problemErr *problem.Error
			if !errors.As(err, &problemErr) || problemErr == nil || !errors.Is(err, injected) {
				t.Fatalf("want a *problem.Error that still unwraps to the cause, got %#v", err)
			}
		})
	}
}

func TestScriptedProblemErrorPreserved(t *testing.T) {
	// Arrange
	original := problem.NewError(probtest.SampleProblem())
	logger := testhelper.NewInMemoryLoggerSink()
	logger.EnqueueResult(original)

	// Act
	err := logger.Emit(interfaces.NewLogRecord(time.Now(), interfaces.LogLevelInfo, "m", nil, nil, nil))

	// Assert
	if !errors.Is(err, original) {
		t.Fatalf("expected the original problem error preserved, got %#v", err)
	}
	probtest.AssertError(t, err, probtest.ExpectID("entity-not-found"), probtest.ExpectStatus(404))
}
