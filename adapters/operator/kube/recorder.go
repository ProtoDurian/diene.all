package kube

import (
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/record"
)

type Recorder interface {
	Event(object runtime.Object, eventtype, reason, message string)
}

type EventRecorder struct {
	recorder record.EventRecorder
}

func NewEventRecorder(recorder record.EventRecorder) EventRecorder {
	return EventRecorder{recorder: recorder}
}

func (e EventRecorder) Event(object runtime.Object, eventtype, reason, message string) {
	e.recorder.Event(object, eventtype, reason, message)
}
