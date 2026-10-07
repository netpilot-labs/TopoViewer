# Issue shapes for adoption boards

Provenance: board 21, 2026-09-06 (BE#699, #700, #701, #703–#706 + FE#468, #707–#709,
#710–#713 + FE#469). Every issue links the board URL and its parent/design issue, states
its bucket and the review date, and ends with a NOT-here list.

## Contents
- Observe-first (adopt-now) issue
- Probe-only issue
- Gated phase (parent + probe + build units)
- Batch cleanup issue
- Labels and ordering

## Observe-first (adopt-now) — label `agent/hold`, p2

Two steps, one PR each; Step B only after Step A's evidence.

```
## Deliverable            one sentence; "robustness, not a cleanup" when true
## What the code shows    file:line facts, verified on the review date
## Change
  Step A — observe: log the new signal beside the current heuristic (stable log key),
           add any hazard guard the bump introduced, run a probe if a value is unknown
  Step B — decide by the signal (after ≥1 week of agreement): switch; old rule = fallback
## Acceptance             zero behavior change in Step A except the guard; suite green
## NOT here               the deletions (→ cleanup issue), sibling candidates
```
Examples: BE#699 (ResultError + ConversationResetMessage), BE#700 (MessageOrigin +
auto-continuation guard), BE#707 (get_context_usage beside the estimate), BE#708
(set_model for same-env models).

## Probe-only — label `agent/hold` (p2/p3), "no product code"

```
## Question(s)            what must be true on OUR path (auth, store, bundled CLI)
## Method                 probe-lab, Lin's Max login (pre-approved), exact scenario + options
## Tier + budget          T0/T1/T2/T3 per probe-testing's ladder; runs and USD cap (n=1 unless a trigger)
## Report on this issue   table + GO/NO-GO or recommendation + the decision points for Lin
## NOT here               no endpoint, no UI, no store changes
```
Examples: BE#704 (fork through PostgresSessionStore), BE#711 (effort × model × thinking
table + subagent spend share), BE#709 (max_budget_usd vs task_budget behavior, low priority).

## Gated phase — parent `agent/stop`, probe `agent/hold`, build units `agent/stop`

Parent body: the defect/pain with code evidence, the fix shape, the sub-issue checklist
with blockers stated ("blocked by R-0 = GO"), the NO-GO fallback, decisions, NOT-here.
Sub-issues attached via GraphQL `addSubIssue` (cross-repo allowed); two levels max.

```
Phase X — <name> (probe decides go/no-go)
  X-0 Probe                    agent/hold   → findings on the issue
  X-1 Backend unit             agent/stop   → blocked by X-0 = GO
  X-2 Frontend unit            agent/stop   → blocked by X-1 (needs/screenshots)
  X-3 Follow-on                agent/stop   → after X-2
```
Examples: Phase R rewind (BE#703), Phase E effort + picker (BE#710; E-3 = retire the
thinking toggle, decided).

## Batch cleanup — label `agent/stop`, p3, explicit trigger

One per week-batch. Body: the trigger ("not before both #A and #B have been live ≥7 days
AND their Step-A logs were read"), the candidate deletions each citing the issue that
proves them, the method (deletions only, one PR per repo, evidence in the PR body), NOT-here
(the text matchers that have no structured equivalent). Every observe-first issue links
it; new inputs are appended as comments ("Added input: …"). Example: BE#701.

## Labels and ordering

- `agent/hold` = an agent may run the probe/observe step to PR-ready; Lin's go starts it.
- `agent/stop` = gated on a probe result or on Lin; never picked up by the loop.
- Priority: adopt-now p2; probes p2 (or p3 when Lin says low priority); cleanup p3.
- Recommended start order: observability PRs → probes → cleanup after the week → phases on
  their probe results → cost levers last.
