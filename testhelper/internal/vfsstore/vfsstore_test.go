package vfsstore_test

import (
	"fmt"
	"slices"
	"testing"

	probtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
	"github.com/ProtoDurian/diene.go-interfaces/lib/interfaces"
	"github.com/ProtoDurian/diene.go-interfaces/testhelper/internal/vfsstore"
)

func TestNormalize(t *testing.T) {
	// Arrange
	cases := map[string]string{
		"":            "/",
		"/":           "/",
		"//a//file":   "/a/file",
		"a/b/":        "/a/b",
		"/a/b/../c/d": "/a/b/../c/d",
	}
	for input, want := range cases {
		// Act
		got := vfsstore.Normalize(input)

		// Assert
		if got != want {
			t.Fatalf("Normalize(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestParent(t *testing.T) {
	// Arrange
	cases := map[string]string{"/": "/", "/file": "/", "/a/file": "/a", "/a/b/c": "/a/b"}
	for input, want := range cases {
		// Act
		got := vfsstore.Parent(input)

		// Assert
		if got != want {
			t.Fatalf("Parent(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestReadsCopyStoredBytes(t *testing.T) {
	// Arrange
	store := vfsstore.New()
	store.Seed(map[string][]byte{"//a//file": []byte("text")}, []string{"/a"})

	// Act
	bytes, bytesErr := store.ReadBytes("/a/file")
	bytes[0] = 'x'
	again, _ := store.ReadBytes("/a/file")
	text, textErr := store.ReadText("/a/file")

	// Assert
	if bytesErr != nil || textErr != nil || string(again) != "text" || text != "text" {
		t.Fatalf("reads: %q %q %v %v", again, text, bytesErr, textErr)
	}
	if !present(store, "/a/file") || present(store, "/nope") {
		t.Fatal("Exists mismatch")
	}
}

func TestFaults(t *testing.T) {
	// Arrange
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/a/file": []byte("t")}, []string{"/a", "/parent", "/parent/child"})
	cases := []struct {
		name string
		run  func() error
		id   string
	}{
		{"write onto a directory", func() error { return store.Write("/a", nil, interfaces.WriteOptions{}) }, "path-is-directory"},
		{"write under a file", func() error { return store.Write("/a/file/x/y", nil, interfaces.WriteOptions{CreateParents: true}) }, "not-a-directory"},
		{"mkdir onto a file", func() error { return store.CreateDirectory("/a/file", interfaces.DirectoryOptions{Recursive: true}) }, "path-is-file"},
		{"mkdir under a file", func() error { return store.CreateDirectory("/a/file/x", interfaces.DirectoryOptions{}) }, "not-a-directory"},
		{"read bytes missing", func() error { _, err := store.ReadBytes("/missing"); return err }, "path-not-found"},
		{"read text missing", func() error { _, err := store.ReadText("/missing"); return err }, "path-not-found"},
		{"write without parent", func() error { return store.Write("/missing/file", nil, interfaces.WriteOptions{}) }, "path-not-found"},
		{"list missing", func() error { _, err := store.List("/missing", interfaces.ListOptions{}); return err }, "path-not-found"},
		{"mkdir without parent", func() error { return store.CreateDirectory("/none/child", interfaces.DirectoryOptions{}) }, "path-not-found"},
		{"delete missing", func() error { return store.Delete("/missing", interfaces.DirectoryOptions{}) }, "path-not-found"},
		{"delete dir with file", func() error { return store.Delete("/a", interfaces.DirectoryOptions{}) }, "directory-not-empty"},
		{"delete dir with dir", func() error { return store.Delete("/parent", interfaces.DirectoryOptions{}) }, "directory-not-empty"},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			// Act
			err := testCase.run()

			// Assert
			probtest.AssertError(t, err, probtest.ExpectID(testCase.id))
		})
	}
}

func TestWriteCreatesParentsOnRequest(t *testing.T) {
	// Arrange
	store := vfsstore.New()

	// Act
	topErr := store.Write("/new", []byte("body"), interfaces.WriteOptions{})
	deepErr := store.Write("/deep/nested/file", []byte("y"), interfaces.WriteOptions{CreateParents: true})

	// Assert
	if topErr != nil || deepErr != nil || !present(store, "/deep/nested") || !present(store, "/deep/nested/file") {
		t.Fatalf("write: %v %v %v", topErr, deepErr, store.Directories())
	}
}

func TestList(t *testing.T) {
	// Arrange
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/a/file": []byte("t"), "/a/sub/deep": nil}, []string{"/a", "/a/sub"})

	// Act
	direct, directErr := store.List("/a", interfaces.ListOptions{})
	recursive, recursiveErr := store.List("/", interfaces.ListOptions{Recursive: true})

	// Assert
	if directErr != nil || recursiveErr != nil {
		t.Fatal(directErr, recursiveErr)
	}
	want := []interfaces.VfsEntry{
		interfaces.NewVfsEntry("/a/file", interfaces.VfsEntryTypeFile, 1, nil),
		interfaces.NewVfsEntry("/a/sub", interfaces.VfsEntryTypeDirectory, 0, nil),
	}
	if !slices.Equal(direct, want) {
		t.Fatalf("direct: %#v", direct)
	}
	if paths := entryPaths(recursive); !slices.Equal(paths, []string{"/a", "/a/file", "/a/sub", "/a/sub/deep"}) {
		t.Fatalf("recursive: %v", paths)
	}
}

func TestSnapshotsAreIndependent(t *testing.T) {
	// Arrange
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/a/file": []byte("t")}, []string{"/a"})

	// Act
	directories := store.Directories()
	directories[0] = "changed"
	files := store.Files()
	files["/a/file"][0] = 'X'

	// Assert
	if !slices.Equal(store.Directories(), []string{"/", "/a"}) || string(store.Files()["/a/file"]) != "t" {
		t.Fatal("snapshots alias stored state")
	}
}

func TestCreateDirectory(t *testing.T) {
	// Arrange
	store := vfsstore.New()

	// Act
	topErr := store.CreateDirectory("/top", interfaces.DirectoryOptions{})
	againErr := store.CreateDirectory("/top", interfaces.DirectoryOptions{})
	deepErr := store.CreateDirectory("/created/a/b", interfaces.DirectoryOptions{Recursive: true})

	// Assert
	if topErr != nil || againErr != nil || deepErr != nil {
		t.Fatal(topErr, againErr, deepErr)
	}
	if !slices.Equal(store.Directories(), []string{"/", "/created", "/created/a", "/created/a/b", "/top"}) {
		t.Fatalf("directories: %v", store.Directories())
	}
}

func TestDelete(t *testing.T) {
	// Arrange
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/a/file": []byte("t"), "/keep": nil}, []string{"/a", "/a/sub"})

	// Act
	fileErr := store.Delete("/keep", interfaces.DirectoryOptions{})
	treeErr := store.Delete("/a", interfaces.DirectoryOptions{Recursive: true})

	// Assert
	if fileErr != nil || treeErr != nil || present(store, "/keep") || present(store, "/a") || present(store, "/a/sub") || len(store.Files()) != 0 {
		t.Fatalf("delete: %v %v %v", fileErr, treeErr, store.Directories())
	}
}

func TestDeleteRootKeepsRoot(t *testing.T) {
	// Arrange
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/child/file": []byte("x")}, []string{"/child"})

	// Act
	err := store.Delete("/", interfaces.DirectoryOptions{Recursive: true})

	// Assert
	if err != nil || !slices.Equal(store.Directories(), []string{"/"}) || len(store.Files()) != 0 {
		t.Fatalf("delete root: %v %v", err, store.Directories())
	}
}

func TestFileAncestor(t *testing.T) {
	// Arrange
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/a/file": nil}, []string{"/a"})
	cases := []struct {
		path   string
		want   string
		wantOK bool
	}{
		{"/a/file/x/y", "/a/file", true},
		{"/a/file/x", "/a/file", true},
		{"/a/file", "", false},
		{"/a/other", "", false},
		{"/", "", false},
	}
	for _, testCase := range cases {
		// Act
		got, ok := store.FileAncestor(testCase.path)

		// Assert
		if got != testCase.want || ok != testCase.wantOK {
			t.Fatalf("FileAncestor(%q) = %q, %v", testCase.path, got, ok)
		}
	}
}

func TestSeedCreatesParents(t *testing.T) {
	// Arrange
	store := vfsstore.New()

	// Act
	store.Seed(map[string][]byte{"/app/config/settings.json": nil}, []string{"/var/log"})

	// Assert
	if !slices.Equal(store.Directories(), []string{"/", "/app", "/app/config", "/var", "/var/log"}) {
		t.Fatalf("directories: %v", store.Directories())
	}
}

func TestSeedPanicsOnKindConflicts(t *testing.T) {
	// Arrange
	cases := []struct {
		name        string
		files       map[string][]byte
		directories []string
		want        string
	}{
		{"file and directory", map[string][]byte{"/p": nil}, []string{"//p/"}, `testhelper: InMemoryVfsOptions seeds "/p" as both a file and a directory`},
		{"root as a file", map[string][]byte{"/": nil}, nil, `testhelper: InMemoryVfsOptions seeds "/" as both a file and a directory`},
		{"file under a file", map[string][]byte{"/p": nil, "/p/q/r": nil}, nil, `testhelper: InMemoryVfsOptions seeds "/p/q/r" under the file "/p"`},
		{"directory under a file", map[string][]byte{"/p": nil}, []string{"/p/q"}, `testhelper: InMemoryVfsOptions seeds "/p/q" under the file "/p"`},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			store := vfsstore.New()

			// Act
			got := panicMessage(func() { store.Seed(testCase.files, testCase.directories) })

			// Assert
			if got != testCase.want {
				t.Fatalf("panic %q, want %q", got, testCase.want)
			}
		})
	}
}

func TestExistsThroughAFile(t *testing.T) {
	// Arrange
	store := vfsstore.New()
	store.Seed(map[string][]byte{"/a/file": nil}, nil)

	// Act
	exists, err := store.Exists("/a/file/child")

	// Assert
	if exists {
		t.Fatal("a path through a file must not exist")
	}
	probtest.AssertError(t, err, probtest.ExpectID("not-a-directory"), probtest.ExpectDetail("/a/file"))
}

func present(store *vfsstore.Store, path string) bool {
	exists, err := store.Exists(path)
	return exists && err == nil
}

func panicMessage(run func()) (message string) {
	defer func() { message = fmt.Sprint(recover()) }()
	run()
	return ""
}

func entryPaths(entries []interfaces.VfsEntry) []string {
	paths := make([]string, len(entries))
	for index, entry := range entries {
		paths[index] = entry.Path
	}
	return paths
}
