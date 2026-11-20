package tools

import (
	"bytes"
	"net"
	"testing"

	log "github.com/sirupsen/logrus"
)

// A failed connection returns its error (no nil dereference) and the password
// never reaches the log.
func TestSshSudoFailedConnectReturnsErrorAndHidesPassword(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	_, port, _ := net.SplitHostPort(l.Addr().String())
	l.Close() // nothing listens on the port any more

	var buf bytes.Buffer
	old := log.StandardLogger().Out
	log.SetOutput(&buf)
	t.Cleanup(func() { log.SetOutput(old) })

	const secret = "not-a-real-password-value"
	out, err := SshSudo("127.0.0.1", port, "user", secret, "", "true")
	if err == nil {
		t.Fatalf("expected an error, got output %q", out)
	}
	if bytes.Contains(buf.Bytes(), []byte(secret)) {
		t.Fatal("the password was written to the log")
	}
}

func TestRunLocalRejectsEmptyCommand(t *testing.T) {
	if _, err := runLocal(); err == nil {
		t.Fatal("expected an error")
	}
}
