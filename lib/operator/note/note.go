package note

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
)

type Spec struct {
	Title    string
	Body     string
	Category string
	Replicas int32
}

func CopyName(owner string, i int32) string {
	return fmt.Sprintf("%s-copy-%d", owner, i)
}

func Payload(spec Spec) string {
	return spec.Title + "\n" + spec.Body
}

func DesiredCopies(owner string, spec Spec) []string {
	names := make([]string, 0, spec.Replicas)
	for i := range spec.Replicas {
		names = append(names, CopyName(owner, i))
	}
	return names
}

func ReadyCondition(desired, converged int) plan.Condition {
	if converged >= desired {
		return plan.Condition{
			Type:    plan.TypeReady,
			Status:  plan.StatusTrue,
			Reason:  "Converged",
			Message: fmt.Sprintf("all %d owned copies converged", desired),
		}
	}
	return plan.Condition{
		Type:    plan.TypeReady,
		Status:  plan.StatusFalse,
		Reason:  "Converging",
		Message: fmt.Sprintf("%d of %d owned copies converged", converged, desired),
	}
}

func BrakeCondition(message string) plan.Condition {
	return plan.Condition{
		Type:    plan.TypeBlastBrakeTripped,
		Status:  plan.StatusTrue,
		Reason:  "BlastBrakeTripped",
		Message: message,
	}
}
