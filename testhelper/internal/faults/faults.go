// Package faults mints the problem-typed faults and normalizes the errors the testhelper doubles return.
package faults

import (
	"errors"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

// Version is the type-URI version segment of every testhelper fault.
const Version = "v1"

// Portal is the fixed portal every testhelper fault type URI is built from.
func Portal() problem.ErrorPortal {
	return problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.diene.atomicloud.com",
		Landscape: "diene",
		Platform:  "go",
		Service:   "interfaces",
		Module:    "testhelper",
	}
}

// PathNotFound mints the path-not-found (404) fault for path.
func PathNotFound(path string) error {
	return NewIntrinsic("path-not-found", "Path not found", path, 404)
}

// DirectoryNotEmpty mints the directory-not-empty (409) fault for path.
func DirectoryNotEmpty(path string) error {
	return NewIntrinsic("directory-not-empty", "Directory not empty", path, 409)
}

// PathIsDirectory mints the path-is-directory (409) fault for a file write onto a directory.
func PathIsDirectory(path string) error {
	return NewIntrinsic("path-is-directory", "Path is a directory", path, 409)
}

// PathIsFile mints the path-is-file (409) fault for a directory create onto a file.
func PathIsFile(path string) error {
	return NewIntrinsic("path-is-file", "Path is a file", path, 409)
}

// NotADirectory mints the not-a-directory (409) fault for a path whose ancestor is a file.
func NotADirectory(path string) error {
	return NewIntrinsic("not-a-directory", "Not a directory", path, 409)
}

// TerminalNotScripted mints the terminal-result-not-scripted (500) fault for executable.
func TerminalNotScripted(executable string) error {
	return NewIntrinsic("terminal-result-not-scripted", "Terminal result not scripted", executable, 500)
}

// Normalize wraps a plain error into a *problem.Error that still unwraps to it; nil and problem errors pass through.
func Normalize(err error) error {
	if err == nil {
		return nil
	}
	var problemErr *problem.Error
	if errors.As(err, &problemErr) && problemErr != nil {
		return err
	}
	return problem.WrapError(problem.FromObject(err, problem.DefaultTransformOptions()), err)
}

// NewIntrinsic builds a problem-typed fault whose type URI comes from Portal.
func NewIntrinsic(id, title, detail string, status int) error {
	typeURI, _ := problem.TypeURI(Portal(), Version, id)
	occurrence := detail
	return problem.NewError(problem.Problem{
		Type:   typeURI,
		Title:  title,
		Status: status,
		Detail: &occurrence,
		Data:   map[string]any{"id": id},
	})
}
