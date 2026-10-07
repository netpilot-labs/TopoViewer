---
name: dependency-updates
description: >-
  Runs NetPilot's dependency pass end to end — drains Renovate PRs and the Dependency
  Dashboard, resolves or dispositions Dependabot alerts, merges what the risk tier allows,
  watches the deploy, rolls back an outage and fixes anything smaller forward, and records what it learned in its own
  ledger so the next pass is better. Use when Lin asks to handle, check, or clean up
  dependency updates, Renovate PRs, Dependabot alerts, or a CVE in any NetPilot repo
  (NetPilot-2-Backend, NetPilot-2-Frontend, netpilot-marketing, containerlab-mcp,
  NetPilot-2-LB), when the DevOps loop reaches its dependency step, or when a security
  bump or a red Renovate PR needs a decision. Not for the Claude Agent SDK pin — that walk
  is `sdk-upgrade-adoption`.
---

# Dependency updates — the pass

One **pass** = inventory every open **item** (Renovate PR, Dependabot alert, Dependency
Dashboard entry) across the fleet, give each a **tier** and an **endpoint**, execute, verify
the deploy, and run the **learning pass** so the ledger and this skill improve. The pass
exists because items rot when nobody owns them: a green grouped PR sat 3 weeks
(BE#507), and the upstream release that unblocked a high CVE went unnoticed for 4 weeks
(BE#382 — clerk-backend-api 7.0.0 lifted the cryptography cap on 2026-08-11) —
observed 2026-09-08 at this skill's creation.

**Skills this one leans on (load at the named step, never restate):** `dev-workflow` (every
PR: the two gates, `pr-gates.sh`, merge mechanics, deploy watch, post-merge cleanup, the
always-on guardrails), `issue-labeling` (labels), `sdk-upgrade-adoption` (any
`claude-agent-sdk` item — hand it over, do not walk it here), `skill-maintenance` (the
learning pass's charter), `db-access` (read-only checks such as Neon's Postgres major).

**Reference files (one level deep):**
- [pass.md](pass.md) — mandatory before every pass: the checklist and operational rules.
- `tiers.md` — the tier table (T0–T4), what each tier's gates and endpoint are, the
  grouped-PR rule, and the trust rules the ledger enforces. **The policy core; Lin owns
  its boundaries.**
- `mechanics.md` — exact commands: inventory, adopting a bot PR, dashboard checkboxes,
  changelog and lockfile audits, surgical transitive bumps (uv / pnpm), alert dismissal,
  the revert, post-merge signals per repo.
- `gotchas.md` — verified footguns with provenance (Renovate config traps, pnpm/uv lock
  behavior, per-package traps). Skim before touching the matching surface.
- **The ledger — `netpilot-devops/ledgers/dependency-updates.md`** (NOT a file of this skill):
  fleet snapshot, per-package trust and audit notes, blocked-alert register with re-check
  triggers, dismissal register, incident log, pending proposals. Read at pass start; update at
  pass end. It lives in the consumer repo outside generated skill assets;
  `ledgers/README.md` there holds the contract (Lin, 2026-09-17).
  This skill owns the ledger's SHAPE; that repo owns its CONTENT.
- `learning.md` — the learning pass: rubric, placement, what is self-serve vs Lin's,
  promotion/demotion rules, the evals, the run-report exemplar.
- `scripts/` — the deterministic steps as executable scripts (inventory, trigger checks,
  lockfile diff, release age, dashboard ticks, alert state, revert PR). **Run them, do
  not re-derive them**; the table in `mechanics.md` maps each to its step. Scripts are
  learning assets like every other file here: a script that fails or misleads is fixed
  in the same pass (Lin, 2026-09-08).

## Where state lives

- **Durable, improves every pass:** edit this skill's mapped sources in a scratch clone of
  `lz-networks/netpilot-skills`, then PR/review/merge and controlled regeneration per
  `skill-maintenance`. Consumer `.claude/agent-config.json` identifies each source;
  sync refuses unrecorded local edits. Operational ledgers remain consumer-owned.
- **Cross-pass state is NOT a skill file** — it is the consumer's, at
  `netpilot-devops/ledgers/` (from that repo: `ledgers/dependency-updates.md`). Write it
  in place; there is nothing to push upstream and nothing a sync can revert. Provenance for
  the rule: while the ledger lived inside this skill, pass-641 wrote the vendored copy and
  pass-642's `sync.sh` tried to REVERT that verified cleanup (28cc152) — the convention was
  documented and still missed, so the state moved out of the skill (Lin, 2026-09-17).
- **Per-item state:** GitHub — the PR, the alert, the tracking issue. The ledger points
  at them; it never duplicates their bodies.
- **Per-pass record:** the runner's worklog / daily report (DevOps loop) or the turn
  summary (attended). One exemplar of the report shape lives in `learning.md`; history
  never accumulates inside the skill (Lin, 2026-09-06: durable assets improve, run
  results are removed).

## Run the pass

Before EVERY pass, load [pass.md](pass.md) in full: it owns the executable checklist and
always-on merge, window, cooldown and ride-out rules. Copy its checklist and execute it;
then follow the tier and alert decisions below.

## Tiers in one screen (detail and rationale: `tiers.md`)

| Tier | Items | Endpoint |
|---|---|---|
| **T0 security** | Renovate `[SECURITY]` PR, or an open alert with a patched version | Same pass, first. Gates of the package's own tier; a fix needing a MAJOR of a direct dep is T4 with the verdict prepared |
| **T1 dev/build tooling** | Renovate's `low-risk-dev` group (non-major dev deps, non-0.x) | Renovate automerges on green; a green T1 still open at the window pass is the pass's merge, first in its repo. RED: diagnose, fix-forward or supersede |
| **T2 runtime patch** | runtime dep, `x.y.Z` | Audit clean + Codex + CI → self-merge → deploy watch → on red, impact decides (roll back an outage, else fix forward) |
| **T3 runtime minor** | runtime dep, `x.Y.z` | As T2 → self-merge. A gate short or a watched package: its own PR, the specific post-deploy verification, the extended watch — never a hold (tiers §1) |
| **T4 heavy-gate** | semver-major; CI/workflow files (actions); auth libs; billing libs; runtime images (python/node/postgres); package manager pins; Pulumi providers; anything in NetPilot-2-LB; approval-gated framework groups | Self-merge under the heavier gate: full provider-side audit (§3) for a major — a dev-only major takes §3 step 1 + CI + Codex, no probe or extended watch (tiers §2) — the surface's own check, the extended watch (tiers §2). Bug-fix patch/minor of a T4 package = T2/T3 + surface check. `claude-agent-sdk` → `sdk-upgrade-adoption` |
| **T5 decision** | tiers §2 decision test: product/policy choice embedded; irreversible or data-affecting step; money/auth/user-data change no owned test can verify; a major break | Worked to PR-ready under the T4 gates, then a desk line with the recommendation and the PR link; Lin answers, the pass merges and watches. A break = incident report with the revert done |

The surface list is `dev-workflow`'s (Guardrails). For a DEPENDENCY bump those surfaces
are T4 here — the pass merges them (Lin, 2026-09-09; tiers §6); T5 is the only hold.

## Disposition ladder for an alert

1. **Direct dep, patched version exists** → Renovate opens the PR (`vulnerabilityAlerts`) →
   T0. No PR after one Renovate run → tick the dashboard's manual-job box (mechanics §5),
   then supersede by hand if still absent.
2. **Transitive only** (Renovate opens nothing — e.g. `pip` under `pip-audit`) → surgical
   lock bump (mechanics §6), tiered by exposure: dev-only → T1 endpoint, runtime → T2.
3. **Blocked by a declared range** (a direct dep caps the vulnerable package) → never
   override a framework's range (gotchas.md §2). Tracking issue `agent/stop` +
   a ledger row with a CONCRETE trigger (which package, which version lifts the cap).
   The trigger is re-checked at step 2 of every pass.
4. **No patched version anywhere** → ledger row, re-checked every pass; no issue unless
   the exposure is runtime-reachable (then `agent/stop` + desk line).
5. **Not reachable** (build-time only, dev tool nobody runs, unused API) → dismiss with
   `not_used` and a one-line comment naming the evidence; ledger row with the re-check
   trigger. Dev/build-only exposure is the agent's call; a runtime-reachable
   `tolerable_risk` is Lin's. Dismissed alerts never re-open themselves — the ledger
   row is the only path back.

## Where it runs

- **Attended:** Lin says "run the dependency pass" (or names a repo / a CVE) — this
  checklist, in-session, with the turn summary as the report.
- **Unattended (ratified 2026-09-09; window moved 2026-09-29):** the DevOps loop runs
  steps 1–2 on EVERY pass (T0 items, trigger re-checks, safe-approval ticks, red-PR
  diagnosis, any open deploy watch). The FULL pass is the first pass on or after
  **Saturday 03:00 America/New_York**; every later pass up to **Sunday 22:00** is a window
  pass that keeps draining the queue (steps 3–7) under the one-runtime-merge rule — no
  merge starts after 22:00 Sunday, so every ride-out closes inside the weekend. Renovate
  creates the week's PRs from Friday 21:00 and keeps creating through the window (its
  `schedule` stays open all weekend so `prConcurrentLimit: 3` refills as PRs merge) and
  automerges T1 only in the window's first six hours (`automergeSchedule` Friday 21:00–
  Saturday 03:00, before the loop's first pass, so no bot merge can land inside a runtime
  ride-out) — every green T1 open after that is the pass's own merge (tiers §1). **Closeout = the Monday 01:00 ET pass** (the Sunday 23:00 pass reads
  the last ride-outs and merges nothing): every ride-out read, the ledger snapshot stamped,
  the weekend's merges in the daily report,
  and nothing mergeable left open — a green, gated PR still open at closeout is a desk
  line naming why, never a silent carry (Lin, 2026-09-29: "everything clean by Monday").
  The one legitimate carry: a PR Renovate creates after the Sunday 21:00 pass (the last
  merge-capable one) cannot merge that weekend under any cutoff; the closeout names it
  and the next Saturday's first pass merges it first. Parked items (T5 lines, blocked triggers) stay in the ledger as before.
  Only T0 security merges on any pass. Generated into the loop; skill edits remain canonical only.

## Extension points (add here as passes earn content)

The layout below is a seed, not a contract: passes may add, merge, split, or delete
reference files and scripts when real work shows a better shape — judged on outcome,
production risk, then efficiency (`learning.md` §3; Lin, 2026-09-08).

- A new repo → its row in the ledger (snapshot + trust seeds) and its post-merge signals
  in `mechanics.md` §8; the Renovate config comes from the fleet template
  (`gotchas.md` §1).
- A new never-auto dependency class → `tiers.md` T4 list, pointing at the
  `dev-workflow` guardrail it maps to.
- A new verified trap → `gotchas.md` under its surface, with provenance.
- A new signal that caught (or missed) a bad deploy → `mechanics.md` §8 and the
  incident row.
