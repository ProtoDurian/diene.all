package problem

import "context"

const (
	localErrorID      = "local_error"
	localErrorTitle   = "Local Error"
	localErrorVersion = "v1"
)

// ErrorSink receives the problems [LocalError] captures.
type ErrorSink interface {
	// Capture reports problem, returning any delivery error.
	Capture(ctx context.Context, problem Problem) error
}

// NoopErrorSink is an [ErrorSink] that discards every capture.
type NoopErrorSink struct{}

// Capture discards problem and always succeeds.
func (NoopErrorSink) Capture(_ context.Context, _ Problem) error {
	return nil
}

// LocalError wraps unexpected errors into a `local_error` problem with the message and stack in `data`.
type LocalError struct {
	Sink   ErrorSink
	Portal ErrorPortal
}

// NewLocalError creates a wrapper writing to sink with [LocalErrorPortal].
func NewLocalError(sink ErrorSink) LocalError {
	return LocalError{Sink: sink, Portal: LocalErrorPortal()}
}

// NewLocalErrorWithPortal creates a wrapper writing to sink with portal.
func NewLocalErrorWithPortal(sink ErrorSink, portal ErrorPortal) LocalError {
	return LocalError{Sink: sink, Portal: portal}
}

// Wrap builds the local_error problem and captures it; a capture failure is returned with the envelope.
func (local LocalError) Wrap(ctx context.Context, cause error, stack string) (Problem, error) {
	message := ""
	if cause != nil {
		message = cause.Error()
	}
	typeURI, err := TypeURI(local.Portal, localErrorVersion, localErrorID)
	if err != nil {
		typeURI = blankType
	}
	envelope := Problem{
		Type:        typeURI,
		Title:       localErrorTitle,
		Status:      defaultProblemStatus,
		Detail:      &message,
		Recoverable: false,
		Data: map[string]any{
			"message":    message,
			"stackTrace": stack,
		},
	}
	if local.Sink != nil {
		if captureErr := local.Sink.Capture(ctx, envelope); captureErr != nil {
			return envelope, captureErr
		}
	}
	return envelope, nil
}
