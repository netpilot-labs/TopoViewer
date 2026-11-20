// clabNetemCommand.go
package clabhandlers

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
)

// DeploymentColocated is the deployment type where TopoViewer runs on the
// containerlab host itself, so host commands run locally instead of over SSH.
const DeploymentColocated = "colocated"

const containerlabBinary = "/usr/bin/containerlab"

var (
	// Container and lab node names: what containerlab itself accepts.
	netemNodePattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$`)
	// Linux interface names and containerlab interface aliases (e.g. e1-1, eth1, Ethernet1/1).
	netemInterfacePattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_./:-]{0,63}$`)
	netemDurationPattern  = regexp.MustCompile(`^[0-9]{1,7}ms$`)
	netemRatePattern      = regexp.MustCompile(`^[0-9]{1,9}$`)
	netemPercentPattern   = regexp.MustCompile(`^[0-9]{1,3}(\.[0-9]{1,4})?$`)
)

// netemSetFlags maps every flag the impairment panel sends to its value pattern.
var netemSetFlags = map[string]*regexp.Regexp{
	"-n":           netemNodePattern,
	"-i":           netemInterfacePattern,
	"--delay":      netemDurationPattern,
	"--jitter":     netemDurationPattern,
	"--rate":       netemRatePattern,
	"--loss":       netemPercentPattern,
	"--corruption": netemPercentPattern,
}

var errNetemCommand = errors.New("unsupported impairment command")

// ValidNetemNode reports whether s is an acceptable node name argument.
func ValidNetemNode(s string) bool { return netemNodePattern.MatchString(s) }

// ValidNetemInterface reports whether s is an acceptable interface argument.
func ValidNetemInterface(s string) bool { return netemInterfacePattern.MatchString(s) }

// ParseNetemCommand turns the command string the impairment panel sends into
// an argument vector. Only
//
//	/usr/bin/containerlab tools netem set -n <node> -i <interface> [--delay Nms] [--jitter Nms] [--rate N] [--loss N] [--corruption N]
//	/usr/bin/containerlab tools netem show -n <node>
//
// are accepted: tokens are separated by exactly one space, every flag is known
// and appears once, and every value matches its pattern. The result is passed
// to exec as-is, never to a shell.
func ParseNetemCommand(command string) ([]string, error) {
	if len(command) > 512 {
		return nil, errNetemCommand
	}
	tokens := strings.Split(command, " ")
	if len(tokens) < 6 || tokens[0] != containerlabBinary || tokens[1] != "tools" || tokens[2] != "netem" {
		return nil, errNetemCommand
	}
	action, rest := tokens[3], tokens[4:]
	if len(rest)%2 != 0 {
		return nil, errNetemCommand
	}

	var allowed map[string]*regexp.Regexp
	var required []string
	switch action {
	case "show":
		allowed = map[string]*regexp.Regexp{"-n": netemNodePattern}
		required = []string{"-n"}
	case "set":
		allowed = netemSetFlags
		required = []string{"-n", "-i"}
	default:
		return nil, errNetemCommand
	}

	seen := make(map[string]bool, len(allowed))
	for i := 0; i < len(rest); i += 2 {
		flag, value := rest[i], rest[i+1]
		pattern, ok := allowed[flag]
		if !ok || seen[flag] || !pattern.MatchString(value) {
			return nil, fmt.Errorf("%w: argument %d", errNetemCommand, i/2+1)
		}
		seen[flag] = true
	}
	for _, flag := range required {
		if !seen[flag] {
			return nil, fmt.Errorf("%w: %s is required", errNetemCommand, flag)
		}
	}
	return tokens, nil
}
