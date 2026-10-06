---
name: feature-research
description: Researches a NEW NetPilot feature into an issue-ready plan BEFORE any code — explore fan-out, design panel, adversarial critic, Lin decisions, then a GitHub Project. Use when Lin asks to research, explore, or plan a new feature or capability, especially one spanning repos or needing VM-side/golden-image changes.
---

# Feature research → issue-ready plan

The deliverable is a research folder + a Lin-approved design + a wave-organized issue
breakdown — never code. Created 2026-07-27 from the VM file-transfer research
(`research/vm-file-transfer/` is the reference example).

## 0. Setup

- Folder at workspace root: `research/<feature-slug>/` with `notes/`, `design/`, and (later)
  `README.md`, `DESIGN.md`, `ISSUES.md`. Not in any git repo — it's a working record.
- The folder is FROZEN once the GitHub Project exists; from then on the board + design issue
  are the living truth (project-management readme contract).

## 1. Explore — parallel research agents, one per affected area

Fan out readers (Workflow/Agent) over every area the feature touches. Always include the
**"how does this ship" area** — golden image / deploy / fleet-mix process, not just code:
capability gating, rollout order, and mixed-fleet handling all come from there.

**UI/frontend feature? One lane is ALWAYS the upstream UI provider** (Lin, 2026-08-01;
provenance FE#254 — don't reinvent a wheel the provider ships for free). NetPilot's chat
surface is @assistant-ui; the method generalizes to any provider:
- **Installed source is ground truth for usable-NOW**: read the provider's src under
  `node_modules/` at the PINNED version (CLAUDE.md reference-repos note) — docs describe
  the latest release, not what we run.
- **Docs + changelog define needs-upgrade**: anything requiring a newer version is
  recorded as future-gated, never silently adopted (a provider bump is its own decision).
- **The lane's deliverable is an adopt / compose / build table**: per component, use the
  provider primitive as-is, compose it with house styling, or build custom — with the
  provider option REJECTED only for a written reason. Custom UI over an unexamined
  provider is the anti-pattern this lane exists to prevent.

Per-agent contract:
- Read actual code; cite `path:line` for every load-bearing fact (endpoint signatures, caps,
  auth, timeouts, storage paths, feature flags).
- Write a durable markdown note to `notes/<area>.md` AND return a structured summary
  (summary / key_files / constraints / open_questions).
- Gotcha: sandboxed agents may write to their scratchpad despite an absolute path in the
  prompt — check where files actually landed and copy into `notes/` (2026-07-26).

## 2. Design panel — 2-3 lenses over the notes

Independent designers each read ALL notes and produce a full end-to-end design under one
lens; write to `design/option-<lens>.md`. Proven lens set: **maximal-reuse / minimal new
surface**, **agent-first (tools own the workflow)**, **infra robustness + security** (transfer
planes, quotas, path safety, planning-mode fallback, on-prem parity, rollout). Each design
must state: exact endpoints/schemas, mode matrix (planning vs execution vs old-fleet),
rollout order, and what it deliberately does NOT build.

## 3. Synthesize — you write DESIGN.md and ISSUES.md yourself

- **DESIGN.md** (concise — design docs <~200 lines; code is truth): one-paragraph summary,
  one-line-per-rejected-alternative section, the chosen architecture per component, mode &
  fleet matrix, policy table, rollout order (V33 playbook for VM-side capabilities: repo PR +
  feature flag → dormant backend/frontend → cloud release + image promotion — `golden-image`
  Impact model owns the gates: an image-level change is Lin-gated, a fleet sweep runs only on
  his direction), risks as future board watch-items.
- **ISSUES.md** per the project-management + issue-labeling contracts: umbrella (`agent/stop`)
  + design issue (`agent/stop`, body = DESIGN.md, living) + PR-sized implementation issues in
  waves with **evidence-backed parallel-lane analysis** (two issues touching one file are
  sequenced, not parallel) and per-issue labels, blockers, file pointers, acceptance criteria.
- Verify every number yourself before asserting it (line counts for the boy-scout check,
  caps, tool counts) — explorer claims drift.
- **Un-repo'd components are findings**: if something load-bearing has no source in any repo
  (e.g. a manually-installed binary/hook), adopting + verifying it becomes a p1 research
  issue that gates every dependent change — never assume its behavior (tusd hook, 2026-07-26).

## 4. Adversarial critic — before showing Lin

One high-effort critic agent reads notes + synthesis and hunts: contradictions vs the notes,
uncovered failure modes (enumerate concrete scenarios in the prompt), false parallel claims,
rollout-order errors, missing Lin decisions. Fold every surviving finding back into the docs.

## 5. Decisions — discuss with Lin BEFORE filing anything

- README.md lists every genuinely-Lin call, each WITH a recommendation (options-before-
  building rule). Typical set: tier/pricing gates, caps, UX shape, scope cuts, accepted
  risks, anything touching the golden/on-prem processes.
- **UX flows are decisions, not defaults**: silently-automatic behavior that could surprise a
  user (hidden smart routing) loses to explicit-choice UX (menu item + modal with progress) —
  present the concrete flow and let Lin pick (2026-07-27).
- Cut scope with a **named revisit trigger** (decide-or-drop rule), e.g. "revisit if PostHog
  shows N planning-mode rejects" — never park scope in limbo.

## 6. Handoff — after Lin's answers

Update the docs to APPROVED state (mark decisions resolved with date), then create the
GitHub Project + issues per **project-management** (readme contract, status feed, sub-issue
GraphQL linking) and **issue-labeling** (label at creation; public repos get only
code-scoped issues — ops/infra detail stays in private-repo issues). Save a memory pointing
at the folder + board. Execution proceeds per **dev-workflow**.
