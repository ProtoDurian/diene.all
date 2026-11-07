package testhelper_test

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/ProtoDurian/diene.go-interfaces/lib/interfaces"
	"github.com/ProtoDurian/diene.go-interfaces/testhelper"
)

type reporter interface {
	Errorf(format string, args ...any)
}

type recorder struct{ failures []string }

func (r *recorder) Errorf(format string, args ...any) {
	r.failures = append(r.failures, fmt.Sprintf(format, args...))
}

func isProblem(err error) bool {
	var problemErr *problem.Error
	return errors.As(err, &problemErr) && problemErr != nil
}

func expectProblem(r reporter, step string, err error) {
	if !isProblem(err) {
		r.Errorf("%s: want a problem-typed error, got %v", step, err)
	}
}

func expectNoError(r reporter, step string, err error) {
	if err != nil {
		r.Errorf("%s: unexpected error %v", step, err)
	}
}

func vfsContract(r reporter, vfs interfaces.Vfs) {
	ctx := context.Background()
	if exists, err := vfs.Exists(ctx, "/"); err != nil || !exists {
		r.Errorf("root must exist: %v %v", exists, err)
	}
	if exists, err := vfs.Exists(ctx, "/missing"); err != nil || exists {
		r.Errorf("missing path must not exist: %v %v", exists, err)
	}
	_, err := vfs.ReadText(ctx, "/missing")
	expectProblem(r, "read missing text", err)
	_, err = vfs.ReadBytes(ctx, "/missing")
	expectProblem(r, "read missing bytes", err)
	expectProblem(r, "write without parent", vfs.WriteText(ctx, "/no/parent.txt", "x", interfaces.WriteOptions{}))
	if exists, _ := vfs.Exists(ctx, "/no"); exists {
		r.Errorf("a failed write must not create its parent")
	}
	expectNoError(r, "write text with parents", vfs.WriteText(ctx, "/docs/a.txt", "hi", interfaces.WriteOptions{CreateParents: true}))
	expectNoError(r, "write bytes", vfs.WriteBytes(ctx, "/docs/b.bin", []byte{1, 2, 3}, interfaces.WriteOptions{}))
	if text, textErr := vfs.ReadText(ctx, "/docs/a.txt"); textErr != nil || text != "hi" {
		r.Errorf("read text: %q %v", text, textErr)
	}
	if bytes, bytesErr := vfs.ReadBytes(ctx, "/docs/b.bin"); bytesErr != nil || !slices.Equal(bytes, []byte{1, 2, 3}) {
		r.Errorf("read bytes: %v %v", bytes, bytesErr)
	}
	want := []interfaces.VfsEntry{
		{Path: "/docs/a.txt", Type: interfaces.VfsEntryTypeFile, Size: 2},
		{Path: "/docs/b.bin", Type: interfaces.VfsEntryTypeFile, Size: 3},
	}
	if entries, listErr := vfs.List(ctx, "/docs", interfaces.ListOptions{}); listErr != nil || !slices.Equal(withoutTimes(entries), want) {
		r.Errorf("list direct: %#v %v", entries, listErr)
	}
	expectProblem(r, "mkdir without parent", vfs.CreateDirectory(ctx, "/x/y", interfaces.DirectoryOptions{}))
	expectNoError(r, "mkdir recursive", vfs.CreateDirectory(ctx, "/x/y", interfaces.DirectoryOptions{Recursive: true}))
	if entries, listErr := vfs.List(ctx, "/", interfaces.ListOptions{Recursive: true}); listErr != nil || !slices.Equal(sortedPaths(entries), []string{"/docs", "/docs/a.txt", "/docs/b.bin", "/x", "/x/y"}) {
		r.Errorf("list recursive: %v %v", sortedPaths(entries), listErr)
	}
	_, err = vfs.List(ctx, "/missing", interfaces.ListOptions{})
	expectProblem(r, "list missing", err)
	expectProblem(r, "delete missing", vfs.Delete(ctx, "/missing", interfaces.DirectoryOptions{}))
	expectProblem(r, "delete non-empty", vfs.Delete(ctx, "/docs", interfaces.DirectoryOptions{}))
	expectNoError(r, "delete file", vfs.Delete(ctx, "/docs/a.txt", interfaces.DirectoryOptions{}))
	expectNoError(r, "delete tree", vfs.Delete(ctx, "/docs", interfaces.DirectoryOptions{Recursive: true}))
	if exists, _ := vfs.Exists(ctx, "/docs/b.bin"); exists {
		r.Errorf("a recursive delete must remove descendants")
	}
}

func systemContract(r reporter, system interfaces.System, setEnvironment func(name, value string)) {
	setEnvironment("DIENE_CONTRACT_EMPTY", "")
	if value, err := system.Environment("DIENE_CONTRACT_EMPTY"); err != nil || value == nil || *value != "" {
		r.Errorf("an empty variable is present: %v %v", value, err)
	}
	if value, err := system.Environment("DIENE_CONTRACT_UNSET"); err != nil || value != nil {
		r.Errorf("an unset variable is nil: %v %v", value, err)
	}
	if directory, err := system.CurrentDirectory(); err != nil || !filepath.IsAbs(directory) {
		r.Errorf("current directory must be absolute: %q %v", directory, err)
	}
	if now, err := system.NowUTC(); err != nil || now.Location() != time.UTC {
		r.Errorf("clock must be UTC: %v %v", now, err)
	}
	expectNoError(r, "zero delay", system.Delay(context.Background(), 0))
}

func withoutTimes(entries []interfaces.VfsEntry) []interfaces.VfsEntry {
	stripped := make([]interfaces.VfsEntry, len(entries))
	for index, entry := range entries {
		stripped[index] = interfaces.VfsEntry{Path: entry.Path, Type: entry.Type, Size: entry.Size}
	}
	return stripped
}

func sortedPaths(entries []interfaces.VfsEntry) []string {
	paths := make([]string, len(entries))
	for index, entry := range entries {
		paths[index] = entry.Path
	}
	slices.Sort(paths)
	return paths
}

type osVfs struct{ root *os.Root }

func fault(err error) error {
	if err == nil {
		return nil
	}
	return problem.WrapError(problem.FromObject(err, problem.DefaultTransformOptions()), err)
}

func rooted(name string) string {
	if relative := strings.TrimPrefix(path.Clean("/"+name), "/"); relative != "" {
		return relative
	}
	return "."
}

func (v osVfs) Exists(_ context.Context, name string) (bool, error) {
	_, err := v.root.Lstat(rooted(name))
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	return err == nil, fault(err)
}

func (v osVfs) ReadBytes(_ context.Context, name string) ([]byte, error) {
	bytes, err := v.root.ReadFile(rooted(name))
	return bytes, fault(err)
}

func (v osVfs) ReadText(ctx context.Context, name string) (string, error) {
	bytes, err := v.ReadBytes(ctx, name)
	return string(bytes), err
}

func (v osVfs) WriteBytes(_ context.Context, name string, bytes []byte, options interfaces.WriteOptions) error {
	if options.CreateParents {
		if err := v.root.MkdirAll(path.Dir(rooted(name)), 0o750); err != nil {
			return fault(err)
		}
	}
	return fault(v.root.WriteFile(rooted(name), bytes, 0o600))
}

func (v osVfs) WriteText(ctx context.Context, name, content string, options interfaces.WriteOptions) error {
	return v.WriteBytes(ctx, name, []byte(content), options)
}

func (v osVfs) List(_ context.Context, name string, options interfaces.ListOptions) ([]interfaces.VfsEntry, error) {
	base := rooted(name)
	if _, err := v.root.Stat(base); err != nil {
		return nil, fault(err)
	}
	entries := make([]interfaces.VfsEntry, 0)
	err := fs.WalkDir(v.root.FS(), base, func(current string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil || current == base {
			return walkErr
		}
		info, infoErr := entry.Info()
		if infoErr != nil {
			return infoErr
		}
		listed := interfaces.NewVfsEntry("/"+current, interfaces.VfsEntryTypeFile, info.Size(), nil)
		if entry.IsDir() {
			listed = interfaces.NewVfsEntry("/"+current, interfaces.VfsEntryTypeDirectory, 0, nil)
		}
		entries = append(entries, listed)
		if entry.IsDir() && !options.Recursive {
			return fs.SkipDir
		}
		return nil
	})
	return entries, fault(err)
}

func (v osVfs) CreateDirectory(_ context.Context, name string, options interfaces.DirectoryOptions) error {
	if options.Recursive {
		return fault(v.root.MkdirAll(rooted(name), 0o750))
	}
	return fault(v.root.Mkdir(rooted(name), 0o750))
}

func (v osVfs) Delete(_ context.Context, name string, options interfaces.DirectoryOptions) error {
	if _, err := v.root.Lstat(rooted(name)); err != nil {
		return fault(err)
	}
	if options.Recursive {
		return fault(v.root.RemoveAll(rooted(name)))
	}
	return fault(v.root.Remove(rooted(name)))
}

type osSystem struct{}

func (osSystem) Environment(name string) (*string, error) {
	value, ok := os.LookupEnv(name)
	if !ok {
		return nil, nil
	}
	return &value, nil
}

func (osSystem) CurrentDirectory() (string, error) {
	directory, err := os.Getwd()
	return directory, fault(err)
}

func (osSystem) NowUTC() (time.Time, error) { return time.Now().UTC(), nil }

func (osSystem) Delay(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return fault(ctx.Err())
	case <-timer.C:
		return nil
	}
}

type ignoresCreateParents struct{ interfaces.Vfs }

func (v ignoresCreateParents) WriteText(ctx context.Context, name, content string, _ interfaces.WriteOptions) error {
	return v.Vfs.WriteText(ctx, name, content, interfaces.WriteOptions{CreateParents: true})
}

type plainReadErrors struct{ interfaces.Vfs }

func (v plainReadErrors) ReadText(ctx context.Context, name string) (string, error) {
	text, err := v.Vfs.ReadText(ctx, name)
	if err != nil {
		return "", errors.New(err.Error())
	}
	return text, nil
}

type flatList struct{ interfaces.Vfs }

func (v flatList) List(ctx context.Context, name string, _ interfaces.ListOptions) ([]interfaces.VfsEntry, error) {
	return v.Vfs.List(ctx, name, interfaces.ListOptions{})
}

type alwaysRecursiveDelete struct{ interfaces.Vfs }

func (v alwaysRecursiveDelete) Delete(ctx context.Context, name string, _ interfaces.DirectoryOptions) error {
	return v.Vfs.Delete(ctx, name, interfaces.DirectoryOptions{Recursive: true})
}

type emptyIsUnset struct{ interfaces.System }

func (s emptyIsUnset) Environment(name string) (*string, error) {
	value, err := s.System.Environment(name)
	if value != nil && *value == "" {
		return nil, err
	}
	return value, err
}

type localClock struct{ interfaces.System }

func (s localClock) NowUTC() (time.Time, error) {
	now, err := s.System.NowUTC()
	return now.In(time.FixedZone("local", 3600)), err
}

func newMemoryVfs() interfaces.Vfs { return testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{}) }

func TestVfsContractParity(t *testing.T) {
	// Arrange
	root, err := os.OpenRoot(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = root.Close() })
	implementations := map[string]interfaces.Vfs{"in-memory": newMemoryVfs(), "os": osVfs{root: root}}
	for name, vfs := range implementations {
		t.Run(name, func(t *testing.T) {
			// Act
			report := &recorder{}
			vfsContract(report, vfs)

			// Assert
			if len(report.failures) != 0 {
				t.Fatalf("contract failures: %v", report.failures)
			}
		})
	}
}

func TestVfsContractRejectsKnownBad(t *testing.T) {
	// Arrange
	implementations := map[string]interfaces.Vfs{
		"ignores CreateParents": ignoresCreateParents{newMemoryVfs()},
		"plain read errors":     plainReadErrors{newMemoryVfs()},
		"flat recursive list":   flatList{newMemoryVfs()},
		"always recursive rm":   alwaysRecursiveDelete{newMemoryVfs()},
	}
	for name, vfs := range implementations {
		t.Run(name, func(t *testing.T) {
			// Act
			report := &recorder{}
			vfsContract(report, vfs)

			// Assert
			if len(report.failures) == 0 {
				t.Fatal("the contract accepted a known-bad Vfs")
			}
		})
	}
}

func TestSystemContractParity(t *testing.T) {
	// Arrange
	memory := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	implementations := []struct {
		name   string
		system interfaces.System
		set    func(name, value string)
	}{
		{"in-memory", memory, memory.SetEnvironment},
		{"os", osSystem{}, t.Setenv},
	}
	for _, implementation := range implementations {
		// Act
		report := &recorder{}
		systemContract(report, implementation.system, implementation.set)

		// Assert
		if len(report.failures) != 0 {
			t.Fatalf("%s contract failures: %v", implementation.name, report.failures)
		}
	}
}

func TestSystemContractRejectsKnownBad(t *testing.T) {
	// Arrange
	implementations := map[string]func() (interfaces.System, func(name, value string)){
		"empty is unset": func() (interfaces.System, func(name, value string)) {
			memory := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			return emptyIsUnset{memory}, memory.SetEnvironment
		},
		"local clock": func() (interfaces.System, func(name, value string)) {
			memory := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			return localClock{memory}, memory.SetEnvironment
		},
	}
	for name, build := range implementations {
		t.Run(name, func(t *testing.T) {
			system, set := build()

			// Act
			report := &recorder{}
			systemContract(report, system, set)

			// Assert
			if len(report.failures) == 0 {
				t.Fatal("the contract accepted a known-bad System")
			}
		})
	}
}
