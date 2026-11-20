package clabhandlers

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"strings"
	"testing"

	tools "github.com/asadarafat/topoViewer/go_tools"
	topoengine "github.com/asadarafat/topoViewer/go_topoengine"
	"github.com/usvc/go-config"
)

const panelSet = "/usr/bin/containerlab tools netem set -n clab-lab-r1 -i e1-1 --delay 10ms --jitter 0ms --rate 0 --loss 0 --corruption 0"

func TestParseNetemCommandAccepts(t *testing.T) {
	cases := []string{
		panelSet,
		"/usr/bin/containerlab tools netem show -n clab-lab-r1",
		"/usr/bin/containerlab tools netem set -n clab-lab_r.1 -i Ethernet1/1 --delay 1500ms --loss 12.5",
		"/usr/bin/containerlab tools netem set -i eth1 -n r1",
	}
	for _, c := range cases {
		argv, err := ParseNetemCommand(c)
		if err != nil {
			t.Errorf("%q: unexpected error %v", c, err)
			continue
		}
		if !reflect.DeepEqual(argv, strings.Split(c, " ")) {
			t.Errorf("%q: argv %v", c, argv)
		}
	}
}

func TestParseNetemCommandRejects(t *testing.T) {
	cases := map[string]string{
		"empty":                    "",
		"other binary":             "/bin/sh -c id",
		"relative binary":          "containerlab tools netem show -n r1",
		"other subcommand":         "/usr/bin/containerlab tools veth create -n r1",
		"destroy":                  "/usr/bin/containerlab destroy -a -n r1",
		"other netem action":       "/usr/bin/containerlab tools netem reset -n r1 -i eth1",
		"semicolon":                panelSet + "; id",
		"semicolon glued":          "/usr/bin/containerlab tools netem show -n r1;id",
		"command substitution":     "/usr/bin/containerlab tools netem show -n $(id)",
		"backticks":                "/usr/bin/containerlab tools netem show -n `id`",
		"pipe":                     "/usr/bin/containerlab tools netem show -n r1 | sh",
		"and":                      "/usr/bin/containerlab tools netem show -n r1 && id",
		"redirect":                 "/usr/bin/containerlab tools netem show -n r1 > /etc/passwd",
		"newline":                  "/usr/bin/containerlab tools netem show -n r1\nid",
		"tab":                      "/usr/bin/containerlab tools netem show -n\tr1",
		"double space":             "/usr/bin/containerlab tools netem show -n  r1",
		"leading space":            " /usr/bin/containerlab tools netem show -n r1",
		"trailing space":           "/usr/bin/containerlab tools netem show -n r1 ",
		"quoted value with space":  `/usr/bin/containerlab tools netem show -n "r1 x"`,
		"value starts with dash":   "/usr/bin/containerlab tools netem show -n --topo",
		"double dash":              "/usr/bin/containerlab tools netem show -- -n r1",
		"double dash value":        "/usr/bin/containerlab tools netem set -n r1 -i --",
		"unknown flag":             "/usr/bin/containerlab tools netem set -n r1 -i eth1 --topo /etc/shadow",
		"flag equals form":         "/usr/bin/containerlab tools netem set -n r1 -i eth1 --delay=10ms",
		"duplicate flag":           "/usr/bin/containerlab tools netem set -n r1 -n r2 -i eth1",
		"missing interface":        "/usr/bin/containerlab tools netem set -n r1 --delay 10ms",
		"missing node":             "/usr/bin/containerlab tools netem set -i eth1 --delay 10ms",
		"show with interface":      "/usr/bin/containerlab tools netem show -n r1 -i eth1",
		"flag without value":       "/usr/bin/containerlab tools netem set -n r1 -i",
		"delay without unit":       "/usr/bin/containerlab tools netem set -n r1 -i eth1 --delay 10",
		"delay NaN":                "/usr/bin/containerlab tools netem set -n r1 -i eth1 --delay NaNms",
		"negative rate":            "/usr/bin/containerlab tools netem set -n r1 -i eth1 --rate -1",
		"path traversal node":      "/usr/bin/containerlab tools netem show -n ../../etc",
		"non-ascii":                "/usr/bin/containerlab tools netem show -n ré",
		"null byte":                "/usr/bin/containerlab tools netem show -n r1\x00",
		"too long":                 "/usr/bin/containerlab tools netem show -n " + strings.Repeat("a", 600),
		"node too long":            "/usr/bin/containerlab tools netem show -n " + strings.Repeat("a", 129),
		"env assignment prefix":    "X=1 /usr/bin/containerlab tools netem show -n r1",
		"sudo prefix":              "sudo /usr/bin/containerlab tools netem show -n r1",
		"binary path trick":        "/usr/bin/containerlab/../sh tools netem show -n r1",
		"brace expansion":          "/usr/bin/containerlab tools netem show -n {a,b}",
		"glob":                     "/usr/bin/containerlab tools netem show -n *",
		"variable":                 "/usr/bin/containerlab tools netem show -n $HOME",
		"percent with junk":        "/usr/bin/containerlab tools netem set -n r1 -i eth1 --loss 5%",
		"interface with semicolon": "/usr/bin/containerlab tools netem set -n r1 -i eth1;id",
	}
	for name, c := range cases {
		if argv, err := ParseNetemCommand(c); err == nil {
			t.Errorf("%s: %q accepted as %v", name, c, argv)
		}
	}
}

// fakeRunner records every local command and answers from a table.
type fakeRunner struct {
	calls [][]string
	err   error
}

func (f *fakeRunner) run(argv ...string) ([]byte, error) {
	f.calls = append(f.calls, argv)
	if f.err != nil {
		return nil, f.err
	}
	if len(argv) > 1 && argv[1] == "version" {
		return []byte("    version: 0.83.0\n"), nil
	}
	if len(argv) > 3 && argv[3] == "show" {
		return []byte("│ Interface │ Delay │ Jitter │ Packet Loss │ Rate (Kbit) │ Corruption │\n" +
			"├───────────┼───────┼────────┼─────────────┼─────────────┼────────────┤\n" +
			"│ e1-1      │ 10ms  │ 0s     │ 0.00%       │ 0           │ 0.00%      │\n"), nil
	}
	return []byte("ok"), nil
}

func withRunner(t *testing.T) *fakeRunner {
	t.Helper()
	f := &fakeRunner{}
	old := tools.RunLocal
	tools.RunLocal = f.run
	t.Cleanup(func() { tools.RunLocal = old })
	return f
}

func postImpairment(deployment, param1 string) *httptest.ResponseRecorder {
	body, _ := json.Marshal(map[string]interface{}{"param1": param1})
	r := httptest.NewRequest(http.MethodPost, "/clab-link-impairment", bytes.NewReader(body))
	w := httptest.NewRecorder()
	ClabEdgeSetImpairment(w, r, &topoengine.CytoTopology{}, deployment, "user", "", "127.0.0.1", "")
	return w
}

func TestSetImpairmentColocatedRunsLocally(t *testing.T) {
	f := withRunner(t)
	w := postImpairment(DeploymentColocated, panelSet)
	if w.Code != http.StatusOK {
		t.Fatalf("status %d: %s", w.Code, w.Body.String())
	}
	if len(f.calls) != 1 || !reflect.DeepEqual(f.calls[0], strings.Split(panelSet, " ")) {
		t.Fatalf("calls %v", f.calls)
	}
	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["result"] != "clab-link-impairment endpoint POST executed" {
		t.Errorf("result %v", resp["result"])
	}
}

func TestSetImpairmentColocatedRejectsInjection(t *testing.T) {
	f := withRunner(t)
	for _, c := range []string{
		panelSet + "; id",
		"/usr/bin/containerlab tools netem show -n $(id)",
		"/usr/bin/containerlab tools netem show -n `id`",
		"/usr/bin/containerlab tools netem set -n r1 -i eth1 -- rm",
		"id",
	} {
		if w := postImpairment(DeploymentColocated, c); w.Code != http.StatusBadRequest {
			t.Errorf("%q: status %d", c, w.Code)
		}
	}
	if len(f.calls) != 0 {
		t.Fatalf("a rejected command ran: %v", f.calls)
	}
}

func TestSetImpairmentColocatedBadBody(t *testing.T) {
	f := withRunner(t)
	for _, body := range []string{"", "{", `{"param1": 5}`, `{"param2": "x"}`, `[]`} {
		r := httptest.NewRequest(http.MethodPost, "/clab-link-impairment", strings.NewReader(body))
		w := httptest.NewRecorder()
		ClabEdgeSetImpairment(w, r, &topoengine.CytoTopology{}, DeploymentColocated, "user", "", "127.0.0.1", "")
		if w.Code != http.StatusBadRequest {
			t.Errorf("%q: status %d", body, w.Code)
		}
	}
	if len(f.calls) != 0 {
		t.Fatalf("calls %v", f.calls)
	}
}

func getImpairment(node, iface string) *httptest.ResponseRecorder {
	q := url.Values{"param1": {node}, "param2": {iface}}
	r := httptest.NewRequest(http.MethodGet, "/clab-link-impairment?"+q.Encode(), nil)
	w := httptest.NewRecorder()
	ClabEdgeGetImpairment(w, r, &topoengine.CytoTopology{}, DeploymentColocated, "user", "", "127.0.0.1", "")
	return w
}

func TestGetImpairmentColocatedRunsLocally(t *testing.T) {
	f := withRunner(t)
	w := getImpairment("clab-lab-r1", "e1-1")
	if w.Code != http.StatusOK {
		t.Fatalf("status %d: %s", w.Code, w.Body.String())
	}
	want := [][]string{
		{"/usr/bin/containerlab", "tools", "netem", "show", "-n", "clab-lab-r1"},
		{"/usr/bin/containerlab", "version"},
	}
	if !reflect.DeepEqual(f.calls, want) {
		t.Fatalf("calls %v", f.calls)
	}
	var resp struct {
		Data map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Data["delay"] != "10ms" {
		t.Errorf("data %v", resp.Data)
	}
}

func TestGetImpairmentColocatedRejectsBadArguments(t *testing.T) {
	f := withRunner(t)
	for _, c := range [][2]string{
		{"r1; id", "eth1"}, {"$(id)", "eth1"}, {"`id`", "eth1"}, {"--topo", "eth1"},
		{"r1", "eth1 x"}, {"r1", "-i"}, {"", "eth1"}, {"r1", ""}, {"r 1", "eth1"},
	} {
		if w := getImpairment(c[0], c[1]); w.Code != http.StatusBadRequest {
			t.Errorf("%q: status %d", c, w.Code)
		}
	}
	if len(f.calls) != 0 {
		t.Fatalf("calls %v", f.calls)
	}
}

func TestGetImpairmentColocatedCommandFailure(t *testing.T) {
	f := withRunner(t)
	f.err = errors.New("boom")
	if w := getImpairment("r1", "eth1"); w.Code != http.StatusInternalServerError {
		t.Errorf("status %d", w.Code)
	}
}

func TestPythonActionGoneInColocatedMode(t *testing.T) {
	f := withRunner(t)
	conf := config.Map{"deployment-type": &config.String{Default: DeploymentColocated}}
	conf.LoadFromEnvironment()
	r := httptest.NewRequest(http.MethodPost, "/python-action", strings.NewReader(`{"param1":"r1","param2":"id"}`))
	w := httptest.NewRecorder()
	PythonActionHandler(w, r, &topoengine.CytoTopology{}, t.TempDir()+"/", conf)
	if w.Code != http.StatusGone {
		t.Fatalf("status %d", w.Code)
	}
	if len(f.calls) != 0 {
		t.Fatalf("calls %v", f.calls)
	}
}
