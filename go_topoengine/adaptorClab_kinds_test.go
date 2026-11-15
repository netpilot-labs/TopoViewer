package topoengine

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// netpilotKinds is every containerlab kind NetPilot deploys
// (containerlab-mcp config.py DEVICE_TYPE_MAPPINGS). The containerlab library
// pinned in go.mod must parse each one: an unknown kind fails
// GenerateClabTopoFromYaml and topoviewer exits rc=1 for that lab
// (containerlab-mcp#389 — mikrotik_chr and vyosnetworks_vyos on v0.60.0).
// Add a kind here when NetPilot adds one.
var netpilotKinds = []string{
	"arista_ceos", "aruba_aoscx", "cisco_iol", "cisco_n9kv", "cisco_xrd",
	"dell_ftosv", "fortinet_fortigate", "juniper_crpd", "juniper_vjunosrouter",
	"juniper_vjunosswitch", "linux", "mikrotik_chr", "nokia_srlinux",
	"paloalto_panos", "sonic-vs", "vyosnetworks_vyos",
}

// repoRoot: GenerateClabTopoFromYaml resolves the export template and
// html-public/ relative to its cwd, which is the install dir in production.
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, _ := runtime.Caller(0)
	return filepath.Dir(filepath.Dir(file))
}

func TestGenerateClabTopoFromYaml_EveryNetPilotKind(t *testing.T) {
	root := repoRoot(t)
	work := t.TempDir()
	// A scratch cwd holding the production template, so html-public/<lab>
	// lands in the temp dir and not in the checkout.
	tmplDir := filepath.Join(work, "html-template", "clab")
	if err := os.MkdirAll(tmplDir, 0o755); err != nil {
		t.Fatal(err)
	}
	tmpl, err := os.ReadFile(filepath.Join(root, "html-template", "clab", "clab-cytoscape-export.tmpl"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmplDir, "clab-cytoscape-export.tmpl"), tmpl, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(work, "html-public"), 0o755); err != nil {
		t.Fatal(err)
	}

	var nodes, links strings.Builder
	for i, kind := range netpilotKinds {
		fmt.Fprintf(&nodes, "    n%d:\n      kind: %s\n      image: example/%s:1\n", i, kind, strings.ReplaceAll(kind, "_", "-"))
		if i > 0 {
			fmt.Fprintf(&links, "    - endpoints: [\"n%d:eth%d\", \"n%d:eth1\"]\n", 0, i, i)
		}
	}
	topo := "name: kinds\ntopology:\n  nodes:\n" + nodes.String() + "  links:\n" + links.String()
	topoFile := filepath.Join(work, "kinds.clab.yml")
	if err := os.WriteFile(topoFile, []byte(topo), 0o644); err != nil {
		t.Fatal(err)
	}

	prev, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(work); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chdir(prev) })
	cy := CytoTopology{}
	jsonPath, err := cy.GenerateClabTopoFromYaml(topoFile)
	if err != nil {
		t.Fatalf("GenerateClabTopoFromYaml: %v", err)
	}
	raw, err := os.ReadFile(jsonPath)
	if err != nil {
		t.Fatal(err)
	}
	// The export must be the full template, not containerlab's minimal
	// name+type fallback (a template incompatible with the library version).
	var export struct {
		Nodes []struct {
			ShortName string `json:"shortname"`
			Kind      string `json:"kind"`
		} `json:"nodes"`
		Links []struct {
			A struct {
				Node      string `json:"node"`
				Interface string `json:"interface"`
			} `json:"a"`
			Z struct {
				Node      string `json:"node"`
				Interface string `json:"interface"`
			} `json:"z"`
		} `json:"links"`
	}
	if err := json.Unmarshal(raw, &export); err != nil {
		t.Fatalf("export is not valid JSON: %v\n%.400s", err, raw)
	}
	got := map[string]string{}
	for _, n := range export.Nodes {
		got[n.ShortName] = n.Kind
	}
	for i, kind := range netpilotKinds {
		if got[fmt.Sprintf("n%d", i)] != kind {
			t.Errorf("node n%d: kind %q in export, want %q", i, got[fmt.Sprintf("n%d", i)], kind)
		}
	}
	if len(export.Links) != len(netpilotKinds)-1 {
		t.Errorf("export has %d links, want %d", len(export.Links), len(netpilotKinds)-1)
	}
	for _, l := range export.Links {
		if l.A.Node != "n0" || !strings.HasPrefix(l.Z.Node, "n") || l.A.Interface == "" || l.Z.Interface != "eth1" {
			t.Errorf("link endpoints not exported: %+v", l)
		}
	}

	// And the export must go through the Cytoscape model the viewer serves.
	if _, err := cy.UnmarshalContainerLabTopoV2(raw, "clab", nil); err != nil {
		t.Fatalf("UnmarshalContainerLabTopoV2: %v", err)
	}
}
