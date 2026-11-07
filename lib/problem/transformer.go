package problem

import (
	"errors"
	"fmt"
)

// TransformOptions configures how [FromObject] folds a value into a [Problem].
type TransformOptions struct {
	Portal         ErrorPortal
	Registry       *Registry
	DefaultStatus  int
	DefaultVersion string
}

// DefaultTransformOptions returns options with [LocalErrorPortal], status 500, version v1 and no registry.
func DefaultTransformOptions() TransformOptions {
	return TransformOptions{
		Portal:         LocalErrorPortal(),
		DefaultStatus:  defaultProblemStatus,
		DefaultVersion: defaultProblemVersion,
	}
}

// FromObject folds any value into a [Problem]; anything uncatalogued becomes a plain 5xx.
func FromObject(value any, options TransformOptions) Problem {
	if envelope, ok := value.(Problem); ok {
		return envelope
	}
	if err, ok := value.(error); ok {
		// errors.As also matches a typed-nil *Error; reading it would panic.
		var problemErr *Error
		if errors.As(err, &problemErr) {
			if problemErr != nil {
				return problemErr.Problem
			}
			value = nil
		}
	}
	if options.Registry != nil {
		if fields, ok := value.(map[string]any); ok {
			if id, ok := fields["problemId"].(string); ok && id != "" {
				if problemType, found := options.Registry.Lookup(id); found {
					status := problemType.Status
					if status == 0 {
						status = options.DefaultStatus
					}
					typeURI, typeErr := options.Registry.TypeURIFor(problemType)
					if typeErr != nil {
						typeURI = blankType
					}
					var problemData map[string]any
					if value, ok := fields["data"].(map[string]any); ok {
						problemData = value
					}
					return Problem{
						Type:        typeURI,
						Title:       problemType.Title,
						Status:      status,
						Recoverable: problemType.Recoverable,
						Data:        problemData,
					}
				}
			}
		}
	}
	typeURI, err := TypeURI(options.Portal, options.DefaultVersion, UncataloguedProblemID)
	if err != nil {
		typeURI = blankType
	}
	var detail *string
	text := ""
	switch typed := value.(type) {
	case nil:
	case error:
		text = typed.Error()
	case string:
		text = typed
	default:
		text = fmt.Sprint(typed)
	}
	if text != "" {
		detail = &text
	}
	return Problem{
		Type:        typeURI,
		Title:       unexpectedProblemTitle,
		Status:      options.DefaultStatus,
		Detail:      detail,
		Recoverable: false,
	}
}
