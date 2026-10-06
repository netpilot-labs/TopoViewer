<!-- Generated from netpilot-skills/workspaces/topoViewer/CLAUDE.md; edit the source path recorded in .claude/agent-config.json, then run canonical scripts/agent-config.py sync. -->
# TopoViewer - Agent Guide

## Agent configuration source

Maintain this instruction file at `netpilot-skills/workspaces/topoViewer/CLAUDE.md`.
Use `.claude/agent-config.json` to find each skill, reference and agent script’s mapped source
in `/Users/linzhu/agent-config` (`lz-networks/netpilot-skills`). Edit and review those sources,
then regenerate consumer snapshots; consumer files and Codex aliases share the same content.
Project code, worklogs and operational records remain in their owning repository.


## What is TopoViewer?
Network topology visualization tool for Container Lab. Go backend + Cytoscape.js frontend. Provides web UI with interactive graph, SSH terminals to containers, and packet capture.

## Project Structure
```
go_cloudshellwrapper/     # Main backend - CLI, HTTP server, API handlers
  cmd/main.go             # Entry point
  cmdClab.go              # Container Lab command & routes
go_topoengine/            # Topology parsing (YAML/JSON → Cytoscape model)
go_xtermjs/               # WebSocket terminal emulation
go_tools/                 # Utilities (logging, SSH, SCP)
html-static/              # Frontend JS/CSS assets
html-template/clab/       # HTML templates (dev.html.tmpl, index.html.tmpl)
dist/                     # Built artifacts (binary + assets)
```

## Two Installations
| Path | Purpose |
|------|---------|
| `/opt/topoviewer-dev/` | Development source code |
| `/opt/topoviewer/` | Production deployment (copy of dist/) |

## Build & Deploy Workflow

### Quick Deploy (no rebuild needed for template/frontend changes):
```bash
# Copy changed files to production
sudo cp /opt/topoviewer-dev/html-template/clab/*.tmpl /opt/topoviewer/html-template/clab/
sudo cp -r /opt/topoviewer-dev/html-static/* /opt/topoviewer/html-static/

# Restart service
sudo pkill -f "topoviewer clab"
cd /opt/topoviewer && sudo ./topoviewer clab \
  --topology-file-yaml /opt/containerlab/simple-demo/simple-demo.clab.yml \
  --server-port 8080 \
  --deployment-type colocated \
  --clab-user linzhu \
  --allowed-hostnames localhost,127.0.0.1,34.42.33.0,clab1-topo.netpilot.io \
  --clab-server-address 34.42.33.0 &
```

### Full Rebuild (for Go code changes):
```bash
cd /opt/topoviewer-dev
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o dist/topoviewer go_cloudshellwrapper/cmd/main.go
sudo cp dist/topoviewer /opt/topoviewer/topoviewer
# Then restart as above
```

## Key Files to Edit

| Change Type | Files |
|-------------|-------|
| Frontend UI/panels | `html-template/clab/dev.html.tmpl`, `index.html.tmpl` |
| Frontend JS logic | `html-static/js/dev.js` |
| CSS styling | `html-static/css/style.css`, `cy-style-dark.json` |
| API endpoints | `go_cloudshellwrapper/cmdClab.go`, `clabHandlers/*.go` |
| Topology parsing | `go_topoengine/adaptorClab.go` |
| WebSocket/terminal | `go_xtermjs/handler_websocket.go`, `utils.go` |

## Common Issues

### WebSocket fails through reverse proxy/tunnel
Add hostname to `--allowed-hostnames` flag. The check is in `go_xtermjs/utils.go:16-28`.

### JS/CSS changes not reflecting through Cloudflare
Browser and Cloudflare cache JS files aggressively. **Update version parameters** when modifying:

```bash
# Bump ALL versions at once (recommended - use YYYYMMDD format, add letter suffix for same-day updates)
cd /opt/topoviewer-dev
VERSION=20260122  # or 20260122a, 20260122b for multiple updates same day
sed -i "s/terminal.js?v=[0-9a-z]*/terminal.js?v=${VERSION}/g" html-static/js/cloudshell/index.html
sed -i "s/index.html?v=[0-9a-z]*/index.html?v=${VERSION}/g" html-static/js/dev.js
sed -i "s/dev.js?ver=[0-9a-z]*/dev.js?ver=${VERSION}/g" html-template/clab/*.tmpl
```

**Cache chain:** `dev.html.tmpl` → `dev.js` → `cloudshell/index.html` → `terminal.js`

**Current version:** `20260817a` (bump this for next update)

### Verify service is running
```bash
ps aux | grep "topoviewer clab"
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
```

## Terminal Auto-Login by Device Kind
The terminal (`html-static/js/cloudshell/terminal.js`) uses device-specific login commands:

| Kind | Vendor | Credentials | Command |
|------|--------|-------------|---------|
| `linux` + image contains "frr" | FRRouting | - | `docker exec -it <container> vtysh` |
| `linux` | Linux containers | - | `docker exec -it <container> bash` |
| `cisco_iol` | Cisco IOL | admin/admin | `sshpass` |
| `arista_ceos` | Arista cEOS | admin/admin | `sshpass` |
| `juniper_crpd` | Juniper cRPD | root/clab123 | `sshpass` |
| `paloalto_panos` | Palo Alto PAN | admin/Admin@123 | `sshpass` |
| `nokia_srlinux` | Nokia SR Linux | admin/NokiaSrl1! | `sshpass` |
| `vyosnetworks_vyos` | VyOS | admin/admin | `sshpass` |
| `fortinet_fortigate` | Fortinet FortiGate | admin/Fortinet!1234 | `sshpass` |
| Others | Fallback | - | `ssh admin@...` (manual password) |

To add new device types, edit `terminal.js` and add a new `else if (nodeKind === '...')` block.
Reference: https://containerlab.dev/manual/kinds/

## Access URLs
- TopoViewer: `http://localhost:8080` or `https://clab1-topo.netpilot.io`
- ContainerLab Graph: `http://localhost:50081`
