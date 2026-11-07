// Package interfaces defines effect ports whose non-nil errors always carry a *problem.Error.
package interfaces

import (
	"context"
	"maps"
	"time"
)

// System is the process and clock port; Environment returns nil for an unset variable.
type System interface {
	Environment(name string) (*string, error)
	CurrentDirectory() (string, error)
	NowUTC() (time.Time, error)
	Delay(ctx context.Context, d time.Duration) error
}

// TerminalCommand is one process invocation; build it with NewTerminalCommand.
type TerminalCommand struct {
	Executable               string
	Args                     []string
	WorkingDirectory         *string
	Environment              map[string]string
	IncludeParentEnvironment bool
	RunInShell               bool
}

// NewTerminalCommand creates a command with cloned inputs.
func NewTerminalCommand(executable string, args []string, workingDirectory *string, environment map[string]string, includeParentEnvironment bool, runInShell bool) TerminalCommand {
	command := TerminalCommand{
		Executable:               executable,
		Args:                     append([]string(nil), args...),
		Environment:              make(map[string]string, len(environment)),
		IncludeParentEnvironment: includeParentEnvironment,
		RunInShell:               runInShell,
	}
	maps.Copy(command.Environment, environment)
	if workingDirectory != nil {
		copied := *workingDirectory
		command.WorkingDirectory = &copied
	}
	return command
}

// Clone returns a command with independently owned mutable fields.
func (c TerminalCommand) Clone() TerminalCommand {
	return NewTerminalCommand(c.Executable, c.Args, c.WorkingDirectory, c.Environment, c.IncludeParentEnvironment, c.RunInShell)
}

// TerminalOutput is captured output from a completed terminal invocation.
type TerminalOutput struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

// Succeeded reports whether the child exited with code zero.
func (o TerminalOutput) Succeeded() bool { return o.ExitCode == 0 }

// Terminal runs processes; a non-zero exit is output, only a launch failure is an error.
type Terminal interface {
	Run(ctx context.Context, command TerminalCommand) (TerminalOutput, error)
}
