package topoengine

import (
	"encoding/json"
	"strings"
	"testing"
)

// Minimal but structurally valid containerlab topology-data export.
func validTopoJSON(name string, nodeNames ...string) string {
	var nodes []string
	for i, n := range nodeNames {
		nodes = append(nodes, `{
			"id": "`+n+`",
			"index": "`+string(rune('0'+i))+`",
			"shortname": "`+n+`",
			"longname": "clab-`+name+`-`+n+`",
			"fqdn": "`+n+`.`+name+`.io",
			"kind": "nokia_srlinux",
			"image": "ghcr.io/nokia/srlinux",
			"mgmt-ipv4-address": "10.0.0.`+string(rune('2'+i))+`",
			"mgmt-ipv4-prefix-length": 24,
			"labels": {}
		}`)
	}
	return `{
		"name": "` + name + `",
		"type": "clab",
		"nodes": [` + strings.Join(nodes, ",") + `],
		"links": []
	}`
}

func TestUnmarshalContainerLabTopoV2_Valid(t *testing.T) {
	cyTopo := CytoTopology{}
	out, err := cyTopo.UnmarshalContainerLabTopoV2(
		[]byte(validTopoJSON("citest", "r1", "r2")), "clab", nil)
	if err != nil {
		t.Fatalf("valid topology returned error: %v", err)
	}
	if cyTopo.ClabTopoDataV2.Name != "citest" {
		t.Fatalf("lab name = %q, want citest", cyTopo.ClabTopoDataV2.Name)
	}
	if len(cyTopo.ClabTopoDataV2.Nodes) != 2 {
		t.Fatalf("parsed %d nodes, want 2", len(cyTopo.ClabTopoDataV2.Nodes))
	}
	if !strings.Contains(string(out), "clab-citest-r1") {
		t.Fatalf("cytoscape payload missing node longname; got: %.200s", out)
	}
}

func TestUnmarshalContainerLabTopoV2_MalformedJSON(t *testing.T) {
	// Regression for netpilot-labs/TopoViewer#6: the unmarshal error used to be
	// swallowed, serving a zero-valued topology as if the parse succeeded.
	cyTopo := CytoTopology{}
	if _, err := cyTopo.UnmarshalContainerLabTopoV2([]byte(`{"name": `), "clab", nil); err == nil {
		t.Fatal("malformed JSON must return an error")
	}
}

func TestUnmarshalContainerLabTopoV2_TypeInvalid(t *testing.T) {
	// A type-invalid field partially populates the struct; the error must still
	// surface (TopoViewer#6 round 2).
	bad := strings.Replace(validTopoJSON("citest", "r1"),
		`"mgmt-ipv4-prefix-length": 24`, `"mgmt-ipv4-prefix-length": "bad"`, 1)
	cyTopo := CytoTopology{}
	if _, err := cyTopo.UnmarshalContainerLabTopoV2([]byte(bad), "clab", nil); err == nil {
		t.Fatal("type-invalid JSON must return an error")
	}
}

func TestUnmarshalContainerLabTopoV2_DefaultRoleByKind(t *testing.T) {
	// netpilot-labs/TopoViewer#29: an unlabeled vJunos node gets its kind's icon;
	// a topoViewer-role label still wins, and other kinds keep "pe".
	topo := `{"name": "roles", "type": "clab", "links": [], "nodes": [
		{"id": "r1", "kind": "juniper_vjunosrouter", "labels": {}},
		{"id": "s1", "kind": "juniper_vjunosswitch", "labels": {}},
		{"id": "s2", "kind": "juniper_vjunosswitch", "labels": {"topoViewer-role": "spine"}},
		{"id": "n1", "kind": "nokia_srlinux", "labels": {}}
	]}`
	cyTopo := CytoTopology{}
	out, err := cyTopo.UnmarshalContainerLabTopoV2([]byte(topo), "clab", nil)
	if err != nil {
		t.Fatalf("valid topology returned error: %v", err)
	}
	var elems []struct {
		Group string `json:"group"`
		Data  struct {
			ID   string `json:"id"`
			Role string `json:"topoViewerRole"`
		} `json:"data"`
	}
	if err := json.Unmarshal(out, &elems); err != nil {
		t.Fatalf("cytoscape payload is not a JSON array: %v", err)
	}
	want := map[string]string{"r1": "router", "s1": "leaf", "s2": "spine", "n1": "pe"}
	got := map[string]string{}
	for _, e := range elems {
		if e.Group == "nodes" {
			got[e.Data.ID] = e.Data.Role
		}
	}
	for id, role := range want {
		if got[id] != role {
			t.Errorf("node %s role = %q, want %q", id, got[id], role)
		}
	}
}
