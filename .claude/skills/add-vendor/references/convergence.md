# Convergence — pass bar, witnessed lines, ship-or-track (1-h exit, 1-i certification)

Read at loop end and before certifying a guide version. Standing defaults here are
Lin-ratified (2026-08-23) or probe-earned (XRd 2026-08-14; dellos10 2026-08-22; SONiC
2026-09-29). Pacing, judging and bench rules: `probe-loop.md`.

- Pass bar: the 3 GATE scenarios >90 with the guide loaded certify the guide
  for merge; the coverage/hunter pass at loop end must also clear >90 (hunters
  exempt, below) or its findings ship as guide lines in a follow-up version.
  Tolerates one stochastic wobble; never a repeat of a known trap; a hard 100
  loops forever chasing noise.
- **Every SHIPPED guide line must be WITNESSED by a roll before the loop
  certifies (standing default, Lin 2026-08-23).** A scenario passes at >90
  on any guide version that covered its frictions, provided later versions
  only ADDED lines — but an add/change made in response to a scenario's OWN
  latest roll is unwitnessed BY that scenario, and if it's load-bearing for
  it, that scenario gets a targeted re-roll before certification (the freeze
  covers adds OTHER scenarios already witness, not a scenario's own unproven
  fix). A rewritten/removed line, or a FLOW change (e.g. flipping the primary
  config path), re-runs the affected scenarios — flow changes re-run the
  3 gate scenarios (all 12 only if the flow change lands after the loop-end
  coverage pass). Waiving an unwitnessed load-bearing line is Lin's call, not the
  default (dellos10 s10-v10: the v10 log-sweep fix rode the freeze
  unwitnessed → re-rolled → certified at 98 with no waiver).
- **Hunter scenarios are EXEMPT from the numeric bar (standing default, Lin
  2026-08-23)** — an over-ask / day-2 hunter is judged on honest DISPOSITION
  (every impossible ask answered head-on with on-device negative evidence,
  no fake victory) + friction YIELD, not its score. A hunter that stayed
  above 90 harvested nothing; re-rolling it once its discoveries are covered
  text buys a number, not knowledge (dellos10 run 11: 61 numeric /
  honest-disposition PERFECT → exempt; its ~25 rejects became the v7 line
  set). These standing defaults mean the next arc's Ruling 0 states them as
  settled and surfaces only genuinely-new pass-bar questions.
- **A deduction attributable to a NON-target vendor's TRACKED residual (an
  open issue in its owning repo — the SR Linux spine prompt bug, clab-mcp#225)
  does not count against the target vendor's bar — waive it with the issue
  cited; an untracked or unattributed deduction stands (standing default from
  SONiC coverage 04 at 85, 2026-09-29; same class as the ENVIRONMENTAL
  no-deduction rule in Judging).**
- Scenario defects are real outcomes: a scenario can be platform-impossible
  (XRd: BFD, remote-shut carrier, one-sided-shut return path — three
  redesigns). Redesign against the platform facts the probe proved and fold
  those facts into the vendor guide's Not Supported section.
- Judge-proposed guide lines obey the earned-content rule: a candidate the
  agent handled natively (no deduction) is REJECTED.
- **Every judge proposal SHIPS in the next guide version or is EXPLICITLY
  declined/deferred in the ledger with a reason** — and each version bump's
  assembly diff is checked against the open-proposal list before install.
  Silently dropped proposals re-fire at full price: 4 unshipped proposals
  cost ~17 points across two later rolls, and two version assemblies
  dropped clauses without anyone deciding to (dellos10 P-4, 2026-08-22 —
  the loop's biggest self-inflicted cost).
- **Friction channel (XRd lesson, 2026-08-14): scores measure task SUCCESS;
  friction measures COST — collect both.** Every probe run ends with a
  friction log (tool calls burned, workarounds, ambiguous errors, drop-outs
  to raw shell). Each friction finding routes ONE of two ways, asking
  explicitly "could the platform/tool absorb this?": (a) guide line (agent
  discipline is the right fix) or (b) platform issue in clab-mcp (timeouts,
  error text, missing tools). The XRd sweeps found commit half-lands and the
  live-push gap, taught the agent to SURVIVE them, scored 99.5, and shipped
  the tool defects — because the loop's only actuator was guide text.
- **Re-sweep skips never skip command checks**: when a guide rewrite skips
  the full re-run, any rewritten OPERATIONAL command line still gets a
  one-shot bench execution (the rewritten XRd fallback shipped with a
  broken `docker exec` invocation — prose can be reasoned about, commands
  must run).
