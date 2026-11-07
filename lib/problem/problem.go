// Package problem provides RFC 9457 problem errors, the single type-URI builder, the generic catalog and the Problem resource export.
package problem

import (
	"encoding/json"
	"errors"
	"strconv"
)

// UncataloguedProblemID is the id of a problem that no catalog entry describes.
const UncataloguedProblemID = "uncatalogued"

const (
	blankType              = "about:blank"
	unexpectedProblemTitle = "Unexpected problem"
	defaultProblemStatus   = 500
	defaultProblemVersion  = "v1"
)

// Problem is an RFC 9457 envelope with the `data` and `recoverable` extensions.
type Problem struct {
	Type        string
	Title       string
	Status      int
	Detail      *string
	Instance    *string
	Recoverable bool
	Data        map[string]any
}

// MarshalJSON renders the wire form; nil Detail/Instance and empty Data are omitted.
func (p Problem) MarshalJSON() ([]byte, error) {
	out := map[string]any{
		"type":        p.Type,
		"title":       p.Title,
		"status":      p.Status,
		"recoverable": p.Recoverable,
	}
	if len(p.Data) > 0 {
		out["data"] = p.Data
	}
	if p.Detail != nil {
		out["detail"] = *p.Detail
	}
	if p.Instance != nil {
		out["instance"] = *p.Instance
	}
	return json.Marshal(out)
}

// UnmarshalJSON parses the wire form, applying RFC 9457 defaults for absent members.
func (p *Problem) UnmarshalJSON(data []byte) error {
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	if raw == nil {
		return errors.New("problem must be a JSON object")
	}

	problemType := blankType
	if value, ok := raw["type"].(string); ok {
		problemType = value
	}
	title := unexpectedProblemTitle
	if value, ok := raw["title"].(string); ok {
		title = value
	}
	status := defaultProblemStatus
	if value, ok := raw["status"].(float64); ok {
		status = int(value)
	}
	var detail *string
	if value, ok := raw["detail"].(string); ok {
		detail = &value
	}
	var instance *string
	if value, ok := raw["instance"].(string); ok {
		instance = &value
	}
	recoverable := false
	if value, ok := raw["recoverable"].(bool); ok {
		recoverable = value
	}
	var problemData map[string]any
	if value, ok := raw["data"].(map[string]any); ok {
		problemData = value
	}
	*p = Problem{
		Type:        problemType,
		Title:       title,
		Status:      status,
		Detail:      detail,
		Instance:    instance,
		Recoverable: recoverable,
		Data:        problemData,
	}
	return nil
}

// Equal reports whether p and other serialize to the same wire form.
func (p Problem) Equal(other Problem) bool {
	left, leftErr := json.Marshal(p)
	right, rightErr := json.Marshal(other)
	return leftErr == nil && rightErr == nil && string(left) == string(right)
}

// String returns a compact human-readable form of the envelope.
func (p Problem) String() string {
	return "Problem(" + p.Type + ", " + strconv.Itoa(p.Status) + ", " + p.Title + ")"
}
