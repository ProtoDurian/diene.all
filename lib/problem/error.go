package problem

// Error is a problem-typed error that works with errors.Is, errors.As and %w wrapping.
type Error struct {
	Problem Problem
	wrapped error
}

// NewError creates a problem-typed error carrying problem.
func NewError(problem Problem) *Error {
	return &Error{Problem: problem}
}

// WrapError creates a problem-typed error carrying problem and wrapping cause.
func WrapError(problem Problem, cause error) *Error {
	return &Error{Problem: problem, wrapped: cause}
}

// Error implements the error interface, appending the wrapped cause when present.
func (e *Error) Error() string {
	if e == nil {
		return "<nil problem error>"
	}
	if e.wrapped != nil {
		return e.Problem.String() + ": " + e.wrapped.Error()
	}
	return e.Problem.String()
}

// Unwrap returns the wrapped cause, or nil.
func (e *Error) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.wrapped
}
