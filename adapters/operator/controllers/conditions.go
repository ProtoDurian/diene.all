package controllers

import (
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/AtomiCloud/diene.go-base/lib/operator/reconcile"
)

func applyCondition(conditions *[]metav1.Condition, c reconcile.Condition, generation int64, now metav1.Time) {
	meta.SetStatusCondition(conditions, metav1.Condition{
		Type:               c.Type,
		Status:             metav1.ConditionStatus(c.Status),
		Reason:             c.Reason,
		Message:            c.Message,
		ObservedGeneration: generation,
		LastTransitionTime: now,
	})
}
