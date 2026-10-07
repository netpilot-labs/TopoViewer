# The scenario set (1-g) — what to write, in what form

Read before authoring scenarios. The set is 10 coverage + 2 hunters + 5 short prompts, all in
the probe repo (`netpilot-probe-lab`), execution mode. Provenance: `history.md` §1-g.

## Where and in what form

- Author each as a scenario JSON under `scenarios/vendors/<vendor>/`; schema = the
  `Scenario JSON:` section of `probe.py`'s docstring. Every scenario stubs `get_vm_status` with
  execution-mode state (running VM + the vendor image ready) — the default stub says "not
  provisioned" and the agent correctly refuses to deploy.
- An agent builds each scenario AND its validation in the scenario's `notes`: what the probe
  agent must verify in-lab to call it working (routes, pings, protocol state). The probe proves
  outcomes on-device; it never self-declares.
- Iteration during the loop = working files in the main probe-lab checkout, checkpointed to the
  `wip/<vendor>` branch after every judge batch; ONE PR ships the settled scenarios (only) at loop
  end (`probe-loop.md` Harness owns the rule).

## The 10 coverage scenarios

- Research the vendor's common production network scenarios; cover 80%+ of real-world usage:
  protocol mix, scale within node caps, the features buyers of this NOS actually run.
- At least ONE applies a LARGE live config batch to a running device — a multi-section change
  plus the vendor's commit/save flow.
- Mark the 3 GATE scenarios (deploy · live config push · verify) with a top-level
  `"gate": true` (the validator checks it). They are the only ones that iterate with the guide
  (`probe-loop.md` Pacing). A gate without a Linux endpoint verifies on-device with quoted
  `show` output; no endpoint is added just to ping.

## The 2 friction hunters (11 and 12)

- (11) A multi-node challenge that deliberately OVER-ASKS: at least one capability the platform
  does not support (the agent must build the closest honest thing and label the gap) plus a
  failure-injection + verification arc.
- (12) A day-2 live-ops pass on a RUNNING lab: large live batches, a long-running command,
  config readbacks.
- They hunt friction (tool ergonomics, timeouts, readback trust), not coverage; they are exempt
  from the numeric bar (`convergence.md`).
- **Every limitation 1-a's research or the vendor docs CLAIM** ("no data-plane ACL
  enforcement", "no MC-LAG") **is a verification check inside these two** — never a 13th
  scenario. Not Supported carries only what the bench PROVED with quoted device output
  (`device-guide-template.md` rule 4); a claimed limit that passes on the bench ships as a
  supported capability.

## The 5 short user prompts (a required tier, written WITH the set)

- Two or three sentences each, the way a customer types: the outcome only — no addressing
  plan, no node names, no step list (~300 characters against a coverage scenario's ~1,500).
- The NOS's flagship features; one mixes it with an already-shipped vendor; at least two end in
  a failure drill ("…and prove it keeps working", "…how long did the failover take").
- The checks live in the scenario's `notes`, never in the prompt. A miss is a finding to fix in
  the guide or the platform; the prompt is never edited to pass.
- Exemplar: probe-lab `scenarios/vendors/sonic-vs/sonic-vs-1[4-8]-short-*.json`. When they run
  (once at loop end, again after the friction-fix wave): `probe-loop.md` Pacing step 5b.
