package tools

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"time"
)

// localCommandTimeout bounds one local helper command.
const localCommandTimeout = 30 * time.Second

// RunLocal is the function the handlers call to run a command on the host
// TopoViewer itself runs on. It is a variable so tests can replace it.
var RunLocal = runLocal

// runLocal executes argv directly (no shell). A process that is not root gets
// the command through non-interactive sudo, the same privilege the SSH path
// asked for with "sudo <command>".
func runLocal(argv ...string) ([]byte, error) {
	if len(argv) == 0 {
		return nil, errors.New("empty command")
	}
	if os.Geteuid() != 0 {
		argv = append([]string{"sudo", "-n", "--"}, argv...)
	}
	ctx, cancel := context.WithTimeout(context.Background(), localCommandTimeout)
	defer cancel()
	// #nosec G204 -- callers pass a validated argument vector, never a shell string.
	return exec.CommandContext(ctx, argv[0], argv[1:]...).CombinedOutput()
}
