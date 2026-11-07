package problem

import (
	"regexp"
	"strconv"
	"strings"
)

const (
	resourceAPIVersion = "atomi.cloud/v1alpha1"
	resourceKind       = "Problem"
	dnsLabelMax        = 63
	resourceNameMax    = 253
)

var (
	dnsLabelPattern        = regexp.MustCompile(`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`)
	resourceVersionPattern = regexp.MustCompile(`^v[1-9][0-9]*$`)
)

// ResourceIdentity is the row a Problem resource publishes.
type ResourceIdentity struct {
	Platform  string `json:"platform"`
	Service   string `json:"service"`
	Module    string `json:"module"`
	Landscape string `json:"landscape"`
	Version   string `json:"version"`
}

// ResourceMetadata is the Kubernetes metadata of a Problem resource.
type ResourceMetadata struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
}

// ResourceSpec is the identity row plus its `problems[]` entries.
type ResourceSpec struct {
	ResourceIdentity

	Problems []map[string]any `json:"problems"`
}

// Resource is the Problem custom resource for one row.
type Resource struct {
	APIVersion string           `json:"apiVersion"`
	Kind       string           `json:"kind"`
	Metadata   ResourceMetadata `json:"metadata"`
	Spec       ResourceSpec     `json:"spec"`
}

// InvalidResourceError reports why a catalog cannot be emitted as a Problem resource.
type InvalidResourceError struct {
	Field  string
	Value  string
	Reason string
}

// Error implements the error interface.
func (e *InvalidResourceError) Error() string {
	return "problem resource " + e.Field + " " + e.Reason + ", got " + strconv.Quote(e.Value)
}

// ToResource emits the Problem resource for identity, refusing a row that does not match the catalog.
func (c *Catalog) ToResource(identity ResourceIdentity) (Resource, error) {
	if c.portal.Scheme != "https" {
		return Resource{}, &InvalidResourceError{Field: "scheme", Value: c.portal.Scheme, Reason: "must be https"}
	}
	labels := [...]struct {
		name   string
		value  string
		portal string
	}{
		{"platform", identity.Platform, c.portal.Platform},
		{"service", identity.Service, c.portal.Service},
		{"module", identity.Module, c.portal.Module},
		{"landscape", identity.Landscape, c.portal.Landscape},
	}
	for _, label := range labels {
		if len(label.value) > dnsLabelMax || !dnsLabelPattern.MatchString(label.value) {
			return Resource{}, &InvalidResourceError{Field: label.name, Value: label.value, Reason: "must be a DNS-1123 label"}
		}
		if label.value != label.portal {
			return Resource{}, &InvalidResourceError{Field: label.name, Value: label.value, Reason: "must match the catalog portal " + strconv.Quote(label.portal)}
		}
	}
	if !resourceVersionPattern.MatchString(identity.Version) {
		return Resource{}, &InvalidResourceError{Field: "version", Value: identity.Version, Reason: "must look like v1"}
	}
	name := strings.Join([]string{identity.Service, identity.Module, identity.Landscape, identity.Version}, ".")
	if len(name) > resourceNameMax {
		return Resource{}, &InvalidResourceError{Field: "name", Value: name, Reason: "must be at most 253 characters"}
	}
	for _, id := range c.order {
		entry := c.entries[id]
		expected, err := TypeURI(c.portal, identity.Version, entry.ID)
		if err != nil || entry.TypeURI != expected {
			return Resource{}, &InvalidResourceError{Field: "type", Value: entry.TypeURI, Reason: "must be the type URI built for " + strconv.Quote(entry.ID) + " in this row"}
		}
	}
	return Resource{
		APIVersion: resourceAPIVersion,
		Kind:       resourceKind,
		Metadata:   ResourceMetadata{Name: name, Namespace: identity.Platform},
		Spec:       ResourceSpec{ResourceIdentity: identity, Problems: c.ToCRDContent()},
	}, nil
}
