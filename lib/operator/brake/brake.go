package brake

import "fmt"

type Decision struct {
	Tripped bool
	Reason  string
	Message string
}

func Evaluate(existing, deletes, capPercent int) Decision {
	if deletes <= 0 || existing <= 0 {
		return Decision{}
	}
	// deletes/existing > capPercent/100, kept in integers.
	if deletes*100 > capPercent*existing {
		return Decision{
			Tripped: true,
			Reason:  "BlastBrakeTripped",
			Message: fmt.Sprintf("refusing to delete %d of %d owned resources (cap %d%% per tick)", deletes, existing, capPercent),
		}
	}
	return Decision{}
}
