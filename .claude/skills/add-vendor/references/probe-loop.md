# The probe loop — harness, bench ops, pacing, judging

Contents: Harness (env/URL contract, tunnels) · Bench ops (shared-host
discipline) · Pacing (batches, staggering) · Judging (rubric, tainted
avoidance). The pass bar, witnessed lines and ship-or-track: `convergence.md`.

Owns the full 1-h/1-i mechanics; SKILL.md holds only the pointers and gates.
Rules are Lin-ratified (2026-08-13) or probe-earned (XRd 2026-08-14; dellos10
2026-08-22). Budget shape re-ratified by Lin 2026-09-07 (board 22): Sonnet 5,
tiered battery, batch judges — a vendor add is ≤ ~14 runs + 4 judges, not 30–39
Opus runs + 30 judges. The FIRST vendor add under this shape records its
runs / judges / USD on netpilot-probe-lab#30 (board 22's deferred proof).

## Harness (lz-networks/netpilot-probe-lab)

- `harness.py` builds the PRODUCTION agent client (real `create_claude_client`:
  prompts, tool surface, hooks, denies; device-guide skills auto-load from the
  backend checkout it points at). Auth = local `claude` login; no DB, no prod
  backend.
- Execution mode: set `CONTAINERLAB_MCP_URL` to the bench MCP **including
  the server's `/mcp` mount** (e.g. `http://localhost:18082/mcp` over an SSH
  port-forward `-L 18082:localhost:8082`) + `CONTAINERLAB_MCP_TOKEN` (bench
  `/etc/fastmcp.env` MCP_AUTH_TOKEN) so containerlab tools are REAL. A bare
  host:port POSTs to `/` → 404 → the agent runs tool-less and honestly
  aborts (2 wasted runs, dellos10 s10 re-roll, 2026-08-22).
- **Stale tunnels outlive bench restarts.** An SSH forward from an earlier
  session keeps the local port LISTENING while forwarding into a dead
  connection, and a curl "port answers" check passes on it. Before any
  probe launch: kill existing listeners on the port (`lsof -nP -i :18082`)
  and demand a real HTTP status THROUGH the fresh tunnel (dellos10
  re-roll attempt 1, 2026-08-22).
- Run: `probe.py scenarios/vendors/<vendor>/<x>.json` on the PROD default model
  (Sonnet 5 — the model the guide must carry; it also surfaces more guide gaps).
  `--model claude-opus-5` only for a scenario whose notes carry
  `model_sensitive: true`. Runs land under `runs/` — SCRATCH (git-ignored): the
  evidence is the batch judge's verdict block + decisive lines quoted on the
  vendor issue; run folders are deleted at loop end (probe-testing cleanup).
- Launch probes from the MAIN probe-lab checkout, never a PR worktree — the
  rule and its provenance live in `probe-testing` (always-on mechanics).
- Scenario iteration during the loop = working files in the main checkout,
  pushed to a `wip/<vendor>` branch after every judge batch (the hand-off
  checkpoint — nothing lives only on one machine, SKILL.md); ONE PR ships
  the settled scenarios (only) at loop end, and the wip branch is deleted.
- Scenarios must stub `get_vm_status` with execution-mode state (running VM +
  the vendor image ready) — the default stub says "not provisioned" and the
  agent correctly refuses to deploy.

## Bench ops (shared-host discipline; dellos10-earned 2026-08-22 unless tagged)

- **Recon foreign labs from FILES only — never their CLIs or containers.**
  A recon that ran CLI against the neighbor run's lab killed a scrapli
  session there (03-baseline); even read-only `docker exec` probes into
  foreign containers are off-limits.
- Never `pkill -f`/`pgrep -f` over `gcloud ssh` with a pattern that matches
  the remote command string itself — it kills/matches YOUR OWN session
  (twice). Use exact PIDs, or `pgrep -x` with the 15-char comm truncation
  (`qemu-system-x86`, never `qemu-system-x86_64` — it can't match).
- Pipes eat remote verdicts: `cmd | tail` through gcloud ssh loses the
  decisive lines ≥3 separate times — write a marker file on the bench and
  read it back whole.
- Raw console bytes trip grep's binary detection — `strings` first.
- Cap/stagger concurrent VM-NOS QEMU boots: the OS10 sshd-wedge class is
  load-correlated (3 sightings, all under 5 concurrent boots; solo re-test
  3/3 clean) — a boot storm can wedge device SSH while the NOS stays
  healthy on console.
- **One bench, several lanes** (board 31 feedback lane, 2026-09-30): name
  every lab with the lane's issue prefix and destroy ONLY those, by name —
  Pacing step 6's destroy-all and `docker network prune` are for a bench
  you hold alone; a lab the AGENT names gets the prefix from a scratch
  copy of the scenario ("Name the lab f9-srl06.", BE PR#954). Never stop
  the VM: the coordinator does (a lane that stopped it killed a sibling's run). The probe lock does not serialize
  lanes on different forward ports (`probe-testing/probe-recipes.md` §F).
- **Bench-prove an UNMERGED containerlab-mcp tree by running the real
  service locally through an SSH forward to the node** — never swap the
  bench's installed tree under the MCP endpoint sibling lanes are using
  (clab PR#258, 2026-10-01).
- **Measure a friction the run reported on the run's OWN lab, before
  destroying it** — afterwards the same answer costs a fresh build (the SR
  Linux multihop-session timing came from two redeploys of the probe's
  lab, BE PR#935, 2026-10-01). Final numbers come from a FRESH deploy that
  carries only the final lines: leftovers of the discriminating experiments
  kept a BGP session `Idle` on the lab they ran on (BE PR#955, 2026-10-02).

## Pacing (tiered battery — Lin, 2026-09-07)

The scenarios split into a GATE set, a COVERAGE set and the SHORT prompts
(`scenarios.md`). Gate = the 3 smoke
scenarios (deploy · live config push · verify), marked with a top-level
`"gate": true`; they are the only ones that iterate with the guide. A gate
verifies on-device (quoted `show` output) when the scenario has no Linux
endpoint — do not add hosts just to ping (lab#40, 2026-09-08). Coverage =
the other 7 + the 2 hunters; they run ONCE on the settled guide at loop end,
and the 5 short prompts after them (step 5b).

1. First-ever probe on a fresh harness runs SOLO (smokes the plumbing) —
   `probe.py --dry-run` first (0 tokens; lab 2a), then one live gate scenario.
2. Baseline = ONE run per gate scenario, NO guide — the native-failure
   baseline that seeds the guide (not 3–4 runs).
3. Install the guide as a REAL skill file in the backend checkout
   (uncommitted on main; auto-loads — this also exercises skill DISCOVERY:
   baselines showed the agent loading the WRONG vendor's guide). Every
   version bump is pushed to the backend's `wip/<vendor>-guide` branch, the
   same hand-off checkpoint as the scenarios (Harness); the Phase 2 backend
   PR carries the certified version and the wip branch is deleted.
4. Every following iteration = the 3 gate scenarios WITH the current guide,
   one judge for the batch; the guide improves BETWEEN iterations. Once the
   guide exists, NO run is ever guide-less again. Expect ~2 iterations.
5. Loop end: the 9 coverage + hunter scenarios once, in batches of 3–4 with
   one judge per batch. A FLOW change after this point re-runs the 3 gate
   scenarios, not all 12.
5b. Then the 5 short prompts, back to back on ONE bench with each earlier lab
   left RUNNING — a second chat beside a live lab is a customer's normal state,
   and only that showed a chat destroying another chat's lab and the mgmt-subnet
   clash (clab#248) — `get_vm_status` stubbed from the bench's real state
   (`probe-testing/probe-recipes.md` §H), one judge. A miss is a finding to fix
   in the guide or the platform; the prompt is never edited to pass. They run
   AGAIN after the friction-fix wave, on the bench's `-dev` package and final guides:
   the wave exits when every prompt is at or above its first score with its
   goal met (one re-roll for a wobble; probe-lab#72), and the friction that
   after-run reports is triaged by the arc (friction-report.md).
6. Batch size: total nodes × per-node RAM ≤ half the bench RAM; stagger
   launches ~90s (concurrent set_topology calls race the mgmt-subnet
   allocator). Between batches: destroy all labs (`--cleanup`), remove lab
   dirs, `docker network prune -f` (leftover networks squat the default
   mgmt subnet).

## Judging (agent-judged, never keyword-matched)

One judge per BATCH of 3–4 runs on the same guide version (Haiku 4.5 for the
rubric; Sonnet only when a fabrication call is close), spawned in the
FOREGROUND by the lane that owns the runs, after a coded pre-pass has listed
each run's tool-call count, failed calls, and the `ok:true` write ledger. The
judge reads the scenario (pass checks live in its `notes`) and transcript.md —
events.jsonl only for a disputed quote — verifying every pass check has QUOTED
device output (claimed-without-evidence = −15). Output = a fixed ≤15-line
block per run: score, FIRED/AVOIDED table, friction list, proposed lines. Its
FIRST line is the assigned run FOLDER + that folder's `summary.json`
`num_turns`/`total_cost_usd`, verified before scoring; the lane hands the judge
folder paths and the judge scores exactly those, never a folder it resolved from
a scenario name (`netpilot-probe-lab/reviews/rubrics/README.md` §Batch-judge — a
Haiku judge scored the BASELINE folders while reporting on the GUIDED batch,
SONiC 2026-09-29, probe-lab#67). Rubric from 100: wrong name/rejected syntax −10 · failed call/retry
−5 · boot-wait miss −10 · wasted detour −5 · commit fumble −10 · goal missed
caps at 30. ENVIRONMENTAL events (subnet clashes from concurrent labs) = NO
deduction when recovery is correct. Fabricated tool-outcome narration = −5 +
flagged (route to the prompt desk, not the vendor guide). Judges also fill a
covered-trap FIRED/AVOIDED table — a guide-covered trap that still fires
means the LINE is ineffective: rewrite it, don't just re-run. In PARALLEL
batches, an AVOIDED verdict scaffolded by reading a foreign lab's files is
marked **tainted** — tainted avoidance never justifies dropping or
withholding a guide line (03-baseline's ethN "avoidance" came from the
neighbor's clab.yml; a clean bench would have fired it — dellos10,
2026-08-22).
