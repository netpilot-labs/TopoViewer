# Lin's decision patterns for SDK/CLI feature adoption

Provenance: board 20 (SDK 0.2.130 → 0.2.152) and the board-21 candidate review,
2026-09-06. Apply these BEFORE putting a question to Lin; put only what they do not
settle on the gaps list, each with a recommendation.

## Contents
- Ground rules
- Bucket rules (adopt / probe / later / drop)
- Product and policy defaults he has already set
- What is his to decide (the gaps list)
- How he asks questions (answer shape)

## Ground rules

1. **Not every feature.** Relevance and benefit to NetPilot's agent flow and applications
   decide. "Novelty" is never a reason.
2. **Adapt to the upstream provider's way.** When the Claude app itself changes a control
   (the thinking toggle became the effort dial), NetPilot follows: retire our control, adopt
   theirs, delete the code the old control needed (BE#713).
3. **Charge exactly what the upstream CLI charges.** No true-ups, no divergence from the
   official rate sheet; our reconciler's expected side follows the sheet (BE#694). A CLI
   price change is a reporting fact, not a billing bug.
4. **Bump first, features after.** Pin-only bump, slim battery unless pricing/alias moves,
   then adoption work against the running bundle (D6/D8, board 20).
5. **Observe first, delete later, batch the deletions.** A new signal is logged beside the
   current heuristic for a week; the switch happens on agreement; deletions from several
   changes go into ONE cleanup issue per week-batch (BE#701) — "we may have several code
   cleanup tasks we can do together after a week."
6. **Probe decides go/no-go for anything with an unknown on our auth path.** File the phase
   with the probe as its first sub-issue and the build units `agent/stop` until the probe
   reports GO (Phase R rewind BE#703, Phase E effort BE#710).
7. **Honest scoring.** He asks "is this pure benefit?" and "can we reduce code?" — answer
   from the code with file:line, count before claiming a reduction, and say "robustness,
   not a line-count win" when that is the truth (BE#699).

## Bucket rules

- **Adopt now** when small, reversible, no guardrail surface, and it either replaces a
  hand-rolled mechanism or closes a hazard the bump introduced (typed errors, message
  origin + the auto-continuation guard, reset-message handling, tool annotations).
- **Probe first** when the value is real but the feature's behavior on our path is
  unverified (Postgres session store forking, control requests mid-turn, OAuth beta
  headers, CLI clamps). The probe is `agent/hold`; the build is `agent/stop`.
- **Later** (row only, no issue) when nothing is failing today and no product plan needs
  it (context measurement was "later" until the context-meter idea; then a probe).
- **Drop** when UI-only with no plan to build that UI ("I don't have any plan to support
  that UI, so drop it now" — subagent text forwarding), or when the agents do not need it
  to coordinate, or when it is an Enterprise/managed-settings feature that never reaches a
  headless OAuth session.
- **Low priority, probe only** for cost ceilings when cost is not a felt problem ("we
  don't see much problem with the cost") — behavior table + recommendation, decision later.

## Product and policy defaults already set (do not re-ask)

- Plan default model: Opus for Team and Signature (incl. Signature-seat holders on a Max
  personal tier), Sonnet elsewhere; the default is the pre-selected row, never a separate
  "Default" entry (FE#466).
- Default model + effort, matching the Claude app: **Sonnet 5 · medium for every plan;
  Opus 5 · high for Team/Signature**; adaptive thinking always on (prod fact 2026-09-07: the
  SDK path's CLI default is `high`, not the interactive app's `xhigh` — read the transcript
  `effort` field before assuming a default); the thinking toggle is
  retired once effort is exposed (BE#710/#713). Fable's default effort: probe proposes.
- Fable audience: Max, Team, Signature only; locked row + tooltip "Requires Max, Team, or
  Signature" elsewhere; backend refuses; `fable` is never pinned by default
  (`ANTHROPIC_DEFAULT_FABLE_MODEL` empty = CLI alias table).
- Mythos ids: blocked outright for every user (BE#693).
- New CLI harness tools: denied by default; sanctioning is Lin's (issue #219 rule).

## What is his to decide (put on the gaps list, with a recommendation)

- Audience gating for a new model or capability (which plans).
- Default values users feel (default effort per plan, cost-cap margins, what a control
  means).
- Whether a user-visible defect gets its own phase now.
- Anything that contradicts one of his earlier explicit rulings (never silently overwrite;
  present the evidence and the options).
- Never: mechanism questions (how, where in the code, which fallback) — those are the
  agent's.

## How he asks, how to answer

He goes candidate by candidate: "what is the benefit?", "is this pure benefit?", "can we
reduce code?", "is this like our current bug?", "is this UI only?". Answer in this order:
what the code does today (file:line), what the feature changes, the concrete benefit (or
the honest lack of one), the cost/risk, then ONE recommendation. Explain options in prose,
never as a picker. When he says "file it", file exactly the shape agreed and stop — do not
start work.
