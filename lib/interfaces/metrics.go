package interfaces

import "time"

// MetricKind identifies how a metric sample is aggregated.
type MetricKind string

// Metric kinds.
const (
	MetricKindCounter   MetricKind = "counter"
	MetricKindGauge     MetricKind = "gauge"
	MetricKindHistogram MetricKind = "histogram"
)

// String returns the portable wire name of k.
func (k MetricKind) String() string { return string(k) }

// MetricRecord is one metric sample; a nil Unit means the metric has no unit.
type MetricRecord struct {
	Timestamp  time.Time
	Name       string
	Kind       MetricKind
	Value      float64
	Unit       *string
	Attributes map[string]any
}

// NewMetricRecord creates a UTC record with copied attributes and optional unit.
func NewMetricRecord(timestamp time.Time, name string, kind MetricKind, value float64, unit *string, attributes map[string]any) MetricRecord {
	record := MetricRecord{Timestamp: timestamp.UTC(), Name: name, Kind: kind, Value: value, Attributes: CloneAttributes(attributes)}
	if unit != nil {
		copied := *unit
		record.Unit = &copied
	}
	return record
}

// Clone returns a record with independently owned attributes and optional unit.
func (r MetricRecord) Clone() MetricRecord {
	return NewMetricRecord(r.Timestamp, r.Name, r.Kind, r.Value, r.Unit, r.Attributes)
}

// MetricsCollector receives structured application metric samples.
type MetricsCollector interface {
	Emit(record MetricRecord) error
}
