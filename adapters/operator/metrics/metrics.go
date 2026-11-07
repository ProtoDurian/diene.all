package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	crmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"
)

const (
	ConditionMetric     = "operator_template_condition"
	LedgerFailureMetric = "operator_template_ledger_failures_total"
	ReconcileTickMetric = "operator_template_reconcile_ticks_total"
)

type Recorder interface {
	Observe(controller string, conditions []metav1.Condition)
	LedgerFailure(controller string)
	Tick(controller string)
}

var (
	conditionGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: ConditionMetric,
		Help: "Operator condition state (1 True, 0 otherwise) by controller and type.",
	}, []string{"controller", "type"})

	ledgerFailures = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: LedgerFailureMetric,
		Help: "Durable-ledger operation failures by controller.",
	}, []string{"controller"})

	reconcileTicks = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: ReconcileTickMetric,
		Help: "Reconcile loop liveness ticks by controller.",
	}, []string{"controller"})

	_ = register()
)

func register() bool {
	crmetrics.Registry.MustRegister(conditionGauge, ledgerFailures, reconcileTicks)
	return true
}

type Prometheus struct{}

func NewPrometheus() Prometheus { return Prometheus{} }

func (Prometheus) Observe(controller string, conditions []metav1.Condition) {
	for i := range conditions {
		value := 0.0
		if conditions[i].Status == metav1.ConditionTrue {
			value = 1.0
		}
		conditionGauge.WithLabelValues(controller, conditions[i].Type).Set(value)
	}
}

func (Prometheus) LedgerFailure(controller string) {
	ledgerFailures.WithLabelValues(controller).Inc()
}

func (Prometheus) Tick(controller string) {
	reconcileTicks.WithLabelValues(controller).Inc()
}
