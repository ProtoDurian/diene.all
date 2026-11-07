package interfaces

import (
	"maps"
	"time"
)

// LogLevel is the severity of a structured log record.
type LogLevel string

// Log levels, from most to least detailed.
const (
	LogLevelTrace   LogLevel = "trace"
	LogLevelDebug   LogLevel = "debug"
	LogLevelInfo    LogLevel = "info"
	LogLevelWarning LogLevel = "warning"
	LogLevelError   LogLevel = "error"
	LogLevelFatal   LogLevel = "fatal"
)

// String returns the portable wire name of l.
func (l LogLevel) String() string { return string(l) }

// LogRecord is one structured log emission.
type LogRecord struct {
	Timestamp  time.Time
	Level      LogLevel
	Message    string
	Attributes map[string]any
	Error      *string
	StackTrace *string
}

// NewLogRecord creates a UTC record with copied attributes and optional strings.
func NewLogRecord(timestamp time.Time, level LogLevel, message string, attributes map[string]any, errorMessage, stackTrace *string) LogRecord {
	record := LogRecord{Timestamp: timestamp.UTC(), Level: level, Message: message, Attributes: CloneAttributes(attributes)}
	if errorMessage != nil {
		copied := *errorMessage
		record.Error = &copied
	}
	if stackTrace != nil {
		copied := *stackTrace
		record.StackTrace = &copied
	}
	return record
}

// Clone returns a record with independently owned attributes and optional strings.
func (r LogRecord) Clone() LogRecord {
	return NewLogRecord(r.Timestamp, r.Level, r.Message, r.Attributes, r.Error, r.StackTrace)
}

// CloneAttributes returns a shallow copy of attributes, or an empty map for nil.
func CloneAttributes(attributes map[string]any) map[string]any {
	if attributes == nil {
		return map[string]any{}
	}
	return maps.Clone(attributes)
}

// LoggerSink receives structured application logs.
type LoggerSink interface {
	Emit(record LogRecord) error
}
