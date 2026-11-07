package plan

type Condition struct {
	Type    string
	Status  string
	Reason  string
	Message string
}

const (
	StatusTrue  = "True"
	StatusFalse = "False"
)

const (
	TypeReady              = "Ready"
	TypeDrifted            = "Drifted"
	TypeConflict           = "Conflict"
	TypeWaitingForEndpoint = "WaitingForEndpoint"
	TypeBlastBrakeTripped  = "BlastBrakeTripped"
)

type Plan struct {
	Creates []string
	Deletes []string
}

func (p Plan) Empty() bool {
	return len(p.Creates) == 0 && len(p.Deletes) == 0
}
