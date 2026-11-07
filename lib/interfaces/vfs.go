package interfaces

import (
	"context"
	"time"
)

// VfsEntryType identifies the kind of a virtual filesystem entry.
type VfsEntryType string

// Virtual filesystem entry kinds.
const (
	VfsEntryTypeFile      VfsEntryType = "file"
	VfsEntryTypeDirectory VfsEntryType = "directory"
	VfsEntryTypeLink      VfsEntryType = "link"
)

// String returns the portable wire name of t.
func (t VfsEntryType) String() string { return string(t) }

// VfsEntry is metadata for one entry; a nil ModifiedAt means no modification time.
type VfsEntry struct {
	Path       string
	Type       VfsEntryType
	Size       int64
	ModifiedAt *time.Time
}

// NewVfsEntry builds an entry and copies modifiedAt, in UTC, when present.
func NewVfsEntry(path string, entryType VfsEntryType, size int64, modifiedAt *time.Time) VfsEntry {
	entry := VfsEntry{Path: path, Type: entryType, Size: size}
	if modifiedAt != nil {
		copied := modifiedAt.UTC()
		entry.ModifiedAt = &copied
	}
	return entry
}

// WriteOptions configures a write; CreateParents creates missing parent directories.
type WriteOptions struct {
	CreateParents bool
}

// VfsWriteOptions is an alias of WriteOptions.
type VfsWriteOptions = WriteOptions

// ListOptions configures a list; Recursive includes all descendants.
type ListOptions struct {
	Recursive bool
}

// VfsListOptions is an alias of ListOptions.
type VfsListOptions = ListOptions

// DirectoryOptions configures create and delete; Recursive creates ancestors or deletes descendants.
type DirectoryOptions struct {
	Recursive bool
}

// VfsDirectoryOptions is an alias of DirectoryOptions.
type VfsDirectoryOptions = DirectoryOptions

// Vfs is a filesystem port; paths are opaque and their normalization belongs to the implementation.
type Vfs interface {
	Exists(ctx context.Context, path string) (bool, error)
	ReadBytes(ctx context.Context, path string) ([]byte, error)
	ReadText(ctx context.Context, path string) (string, error)
	WriteBytes(ctx context.Context, path string, bytes []byte, options WriteOptions) error
	WriteText(ctx context.Context, path string, content string, options WriteOptions) error
	List(ctx context.Context, path string, options ListOptions) ([]VfsEntry, error)
	CreateDirectory(ctx context.Context, path string, options DirectoryOptions) error
	Delete(ctx context.Context, path string, options DirectoryOptions) error
}
