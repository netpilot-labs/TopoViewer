# Device-guide template (1-i)

The vendor guide is the backend skill the production agent loads before designing or
configuring the vendor's device type. Copy the skeleton, fill ONLY what probing earned.
XRd (2026-08-14) is the reference implementation and the source of rules 1–7; rules 8–10
come from the SONiC guide (2026-09/10); rule 11 is Lin's ruling.

## Rules (each one paid for by a real mistake)

1. **Earned content only.** Every line traces to an OBSERVED probe/live failure — never
   what the agent handles natively, never assumed failures. Lines whose failures stop
   reproducing get dropped. Hard cap 300 lines; pass bar and re-run semantics live in
   `convergence.md`.
2. **Never restate platform behavior.** The MCP server instructions and tool
   descriptions own the generic workflow (set_configs pre-deploy, tool ownership of
   files, composition). Restating it in a guide = drift the next platform change turns
   into a lie. A PLATFORM-generic lesson earned during probing (e.g. run_bash is
   /bin/sh, composition exists) routes to the MCP tool description or server
   instructions via a clab-mcp issue — not into the vendor guide. (XRd lesson: the
   composition sentence lived only in the guide, and a production agent half-trusted
   it and hand-wrote the whole access template.)
3. **Prohibitions are enumerated lists, not warnings.** "Never hand-copy that block"
   did not hold; the explicit never-write list did. If the platform composes config
   blocks for this kind, NAME every block the platform owns.
4. **Not-Supported claims carry proof and state what IS valid.** Each limitation names
   its on-device evidence. Overstating a limitation is as costly as missing one —
   "control-plane only" made agents distrust valid ping proofs until it was refined to
   "throughput/QoS unsupported; punt-path ping/traceroute transits fine."
5. **High-level guidance, never cheat-command sequences** — the agent must still think.
6. **No bench artifacts.** Reference only files/tools that exist on PRODUCTION VMs
   (XRd lesson: the guide shipped pointing at a helper script that existed only on the
   probe bench). Verify every path against the golden image / package before shipping.
7. **No image/upload section.** The agent never builds images and `get_vm_status` +
   product context already cover availability — no probe ever showed an agent
   misdirecting here. If one does, the failure earns its lines back.
8. **A line that names a CAUSE has a bench reproduction of that cause.** A plausible story
   from one run is not a line (SONiC v3's "hostif race" line sent a later run into an hour
   of retries — the real cause was an `EthernetN` link name, 2026-09-29). A NUMBER is a range
   with its scope, taken on a second topology with the mechanism sampled on every node that
   sends: "28–32 s" from one lab read 34–47 s on the next (BE PR#958 → PR#961). A convergence
   time is measured ONE-WAY, per sender — a ping shows the slower of its two directions (13 s at
   the leaf next to the cut read 121–180 s on the ping; `tcpdump -tt` of the echo requests
   arriving at each host separates them, BE#963).
9. **A proof line says WHEN its evidence exists.** "Quote `ip route show vrf`" was run
   right after deploy, before any host had sent traffic: empty table, and the run fell back
   to a weaker signal; "AFTER the pings quote …" got the route quoted on the next run
   (sonic-vs-guide symmetric-IRB proof, BE PR#932, 2026-10-01).
10. **A command the guide shows is in the form the device's shell accepts, and a placeholder
   names the TYPE of value.** The agent copies both verbatim: `ping -I <local loopback>` was
   filled with the interface name (100% loss; `<local loopback IP>` is unambiguous) and a bare
   `show bgp summary` is `No such command` on SONiC (`vtysh -c '…'`). Pin the form in the
   guide's test (BE PR#955, 2026-10-02).
11. **Written for the CURRENT VM package only** (Lin, 2026-10-02; `prompt-engineering` rule 17): no
   "from package X on; on an older package …" clause, during the project or at close — a user on
   an older package gets the Update VM prompt.

## Skeleton (omit any section with nothing earned)

```markdown
---
name: <vendor>-guide
description: <NOS> device reference. Use before designing or configuring <kind> in ContainerLab labs.
user-invocable: false
---

## Device Type
- `<device_type>` — one line: role, containerlab kind, image repo, pointer to Not Supported.

## Interface Naming
- Topology-link form vs CLI form (if they differ — XRd: `Gi0-0-0-N` vs
  `GigabitEthernet0/0/0/N`); which interface the platform owns (mgmt).

## Config workflow — device-specific deltas ONLY
- The never-write list (rule 3) when composition applies to this kind.
- Persistence/redeploy traps (state dirs surviving destroy — XRd: xr-storage).
- Startup-config file semantics that differ from CLI entry (XRd: flat
  running-config style; indented re-entry silently dropped).

## Config push & commit/save model
- The device's transaction semantics as probes proved them: commit/save grammar,
  timeout half-lands, submode exits, where errors surface, session/lock recovery.

## Device access — traps in the escape hatch ONLY
- Never how-to (platform-owned); only earned traps agents hit when
  `execute_commands` fails (XRd: the no-TTY hang gives ZERO feedback; echo-only
  pty drivers silently return the command itself — both scored probe failures).

## Readiness
- Empirical boot time, ready markers and their staleness traps, gating probes.

## Verification syntax quirks
- Earned CLI failures: syntax that differs from the family default, quoting,
  output-format gotchas (CRLF), what constitutes PROOF (RIB vs table, timestamps).

## Protocol notes (verified on <version>)
- Per-protocol earned facts: what silently doesn't exchange/install and the
  minimum config that fixes it; scan/convergence lags with wait-before-changing
  guidance.

## Not Supported (<image variant>)
- Each limitation + its on-device proof + the valid alternative (rule 4).

```
