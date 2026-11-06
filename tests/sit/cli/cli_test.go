package cli_test

import (
	"context"
	"os/exec"
	"strings"
	"testing"
)

func TestCompiledArtifactReportsItsInterface(t *testing.T) {
	// Arrange
	ctx := context.Background()

	// Act
	// #nosec G204 -- fixed executable and arguments.
	output, err := exec.CommandContext(ctx, "../../../dist/manager", "--help").CombinedOutput()
	// Assert
	if err != nil {
		t.Fatalf("run compiled artifact: %v\n%s", err, output)
	}
	for _, flag := range []string{"enable-note", "enable-journal", "health-probe-bind-address", "observe"} {
		if !strings.Contains(string(output), flag) {
			t.Fatalf("compiled manager did not report the %s flag\n%s", flag, output)
		}
	}
}
