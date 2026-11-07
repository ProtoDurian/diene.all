package problem

import (
	"net/url"
	"regexp"
	"strconv"
)

var snakeCaseID = regexp.MustCompile(`^[a-z][a-z0-9]*(_[a-z0-9]+)*$`)

// ErrorPortal is the service-tree block every problem type URI is built from.
type ErrorPortal struct {
	Scheme    string
	Host      string
	Landscape string
	Platform  string
	Service   string
	Module    string
}

// LocalErrorPortal is the portal for client-local errors that have no service context.
func LocalErrorPortal() ErrorPortal {
	return ErrorPortal{
		Scheme:    "https",
		Host:      "local.atomi.cloud",
		Landscape: "local",
		Platform:  "go",
		Service:   "app",
		Module:    "core",
	}
}

// InvalidSegmentError reports a type-URI segment that is empty or not a single path segment.
type InvalidSegmentError struct {
	Name  string
	Value string
}

// Error implements the error interface.
func (e *InvalidSegmentError) Error() string {
	return "problem type URI segment " + e.Name + " must be a non-empty single path segment, got " + strconv.Quote(e.Value)
}

// TypeURI builds `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`; it is the only place that formats a type URI.
func TypeURI(portal ErrorPortal, version, id string) (string, error) {
	schemeURI, schemeErr := url.Parse(portal.Scheme + ":")
	if portal.Scheme == "" || schemeErr != nil || schemeURI.Scheme != portal.Scheme || schemeURI.Opaque != "" {
		return "", &InvalidSegmentError{Name: "scheme", Value: portal.Scheme}
	}
	hostURI, hostErr := url.Parse("//" + portal.Host)
	if portal.Host == "" || hostErr != nil || hostURI.Host != portal.Host || hostURI.User != nil ||
		hostURI.Path != "" || hostURI.RawQuery != "" || hostURI.Fragment != "" {
		return "", &InvalidSegmentError{Name: "host", Value: portal.Host}
	}
	segments := [...]struct {
		name  string
		value string
	}{
		{"landscape", portal.Landscape},
		{"platform", portal.Platform},
		{"service", portal.Service},
		{"module", portal.Module},
		{"version", version},
		{"id", id},
	}
	for _, segment := range segments {
		if segment.value == "" || segment.value == "." || segment.value == ".." ||
			url.PathEscape(segment.value) != segment.value {
			return "", &InvalidSegmentError{Name: segment.name, Value: segment.value}
		}
	}
	if !snakeCaseID.MatchString(id) {
		return "", &InvalidSegmentError{Name: "id", Value: id}
	}
	return portal.Scheme + "://" + portal.Host + "/docs/" +
		portal.Landscape + "/" + portal.Platform + "/" + portal.Service + "/" +
		portal.Module + "/" + version + "/" + id, nil
}
