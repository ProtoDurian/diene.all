package reconcile

import (
	"fmt"

	"github.com/AtomiCloud/diene.go-base/lib/operator/brake"
	"github.com/AtomiCloud/diene.go-base/lib/operator/ledger"
	"github.com/AtomiCloud/diene.go-base/lib/operator/note"
	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
)

type Condition = plan.Condition

type Spec = note.Spec

const (
	TypeReady              = plan.TypeReady
	TypeDrifted            = plan.TypeDrifted
	TypeConflict           = plan.TypeConflict
	TypeWaitingForEndpoint = plan.TypeWaitingForEndpoint
	TypeBlastBrakeTripped  = plan.TypeBlastBrakeTripped
	StatusTrue             = plan.StatusTrue
	StatusFalse            = plan.StatusFalse
)

func DesiredNames(owner string, spec Spec) []string {
	return note.DesiredCopies(owner, spec)
}

const (
	EventNormal  = "Normal"
	EventWarning = "Warning"
)

type Event struct {
	Type    string
	Reason  string
	Message string
}

type Owned struct {
	Name    string
	Payload string
}

type LedgerState struct {
	Exists bool
	Phase  ledger.Phase
}

type LedgerPre string

const (
	LedgerPreNone   LedgerPre = "none"
	LedgerPreIntent LedgerPre = "intent"
	LedgerPreAdopt  LedgerPre = "adopt"
)

type Upsert struct {
	Name    string
	Payload string
}

type Input struct {
	Owner    string
	Spec     Spec
	Existing []Owned  // owner-UID-verified owned ConfigMaps only
	Foreign  []string // desired names held by a non-owned object
	Ledger   LedgerState
	Observe  bool
	BrakeCap int
}

type Decision struct {
	Write        bool
	LedgerPre    LedgerPre
	Upserts      []Upsert
	Deletes      []string
	ConfirmAfter bool
	Conditions   []Condition
	Events       []Event
	OwnedCount   int32
}

func Decide(in Input) Decision {
	d := Decision{LedgerPre: LedgerPreNone}

	desiredNames := note.DesiredCopies(in.Owner, in.Spec)
	payload := note.Payload(in.Spec)
	desired := toSet(desiredNames)
	foreign := toSet(in.Foreign)
	ownedPayload := make(map[string]string, len(in.Existing))
	for _, o := range in.Existing {
		ownedPayload[o.Name] = o.Payload
	}

	var upserts []Upsert
	conflict := false
	for _, name := range desiredNames {
		if foreign[name] {
			conflict = true
			continue // never overwrite a foreign object
		}
		if cur, ok := ownedPayload[name]; ok && cur == payload {
			continue // already converged
		}
		upserts = append(upserts, Upsert{Name: name, Payload: payload})
	}

	var deletes []string
	for _, o := range in.Existing {
		if !desired[o.Name] {
			deletes = append(deletes, o.Name)
		}
	}

	if decision := brake.Evaluate(len(in.Existing), len(deletes), in.BrakeCap); decision.Tripped {
		d.Conditions = []Condition{note.BrakeCondition(decision.Message)}
		d.Events = []Event{{EventWarning, "BlastBrakeTripped", decision.Message}}
		d.OwnedCount = count(len(in.Existing))
		return d // freeze, no writes
	}

	if in.Observe {
		pl := plan.Plan{Creates: upsertNames(upserts), Deletes: deletes}
		d.Conditions = []Condition{observe(pl)}
		d.OwnedCount = count(len(in.Existing))
		return d
	}

	d.Write = true
	d.Upserts = upserts
	d.Deletes = deletes
	d.ConfirmAfter = true
	switch {
	case !in.Ledger.Exists:
		d.LedgerPre = LedgerPreIntent
	case in.Ledger.Phase == ledger.PhaseOrphaned:
		d.LedgerPre = LedgerPreAdopt
	default:
		d.LedgerPre = LedgerPreNone
	}

	converged := len(desiredNames) - countMembers(desiredNames, foreign)
	d.OwnedCount = count(converged)
	if conflict {
		d.Conditions = []Condition{conflictCondition(), note.ReadyCondition(len(desiredNames), converged)}
		d.Events = []Event{{EventWarning, "OwnedNameCollision", "a desired ConfigMap name is held by a foreign object"}}
		return d
	}
	d.Conditions = []Condition{note.ReadyCondition(len(desiredNames), converged)}
	d.Events = []Event{{EventNormal, "Converged", "note converged to Ready and ledger confirmed"}}
	return d
}

func WaitingForEndpoint(message string) Condition {
	return Condition{Type: plan.TypeWaitingForEndpoint, Status: plan.StatusTrue, Reason: "LedgerUnavailable", Message: message}
}

func conflictCondition() Condition {
	return Condition{Type: plan.TypeConflict, Status: plan.StatusTrue, Reason: "OwnedNameCollision", Message: "a desired ConfigMap name is held by a foreign object"}
}

func observe(pl plan.Plan) Condition {
	if pl.Empty() {
		return Condition{Type: plan.TypeDrifted, Status: plan.StatusFalse, Reason: "InSync", Message: "observe mode: healthy fleet, empty plan"}
	}
	return Condition{
		Type:    plan.TypeDrifted,
		Status:  plan.StatusTrue,
		Reason:  "WouldApply",
		Message: fmt.Sprintf("observe mode: would upsert %d, delete %d (no writes)", len(pl.Creates), len(pl.Deletes)),
	}
}

func toSet(values []string) map[string]bool {
	set := make(map[string]bool, len(values))
	for _, v := range values {
		set[v] = true
	}
	return set
}

func upsertNames(upserts []Upsert) []string {
	names := make([]string, 0, len(upserts))
	for _, u := range upserts {
		names = append(names, u.Name)
	}
	return names
}

func countMembers(names []string, set map[string]bool) int {
	n := 0
	for _, name := range names {
		if set[name] {
			n++
		}
	}
	return n
}

func count(n int) int32 {
	return int32(n) //nolint:gosec // bounded by the Note CRD replicas maximum
}
