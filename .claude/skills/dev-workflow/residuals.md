# Residual issues — from "accepted as residual" to closed (Lin, 2026-09-05)

Contents: what a residual is · when to triage · the triage pass · drop classes · what needs Lin · closing and building

**The goal is acceptable risk, not fixing every theoretical finding.** A residual issue (`review.md` disposition "accept as
residual" / "defer to an issue", usually one issue per PR bundling 2–13 items, `agent/auto p3`) is a parking place, not a
promise to build. Most are dropped at triage: they were written in the reviewer's frame at the PR's moment, and later PRs
routinely fix or delete what they describe (6 of 25 were moot, board 18). A label alone never gets one worked.

## When to triage
- **At project close** — every residual left open by the project's PRs, before the board closes; the readme names the outcome.
- **When a residual's named revisit trigger fires** (first real customer on the surface, the Sentry alert it predicted).
- **Before starting one for any other reason** — never build from the issue text; triage first.

## The triage pass
```
Residual triage:
- [ ] 1. Read the CURRENT code on the surface each item names. Mark moot: fixed since / surface removed / already alerted.
- [ ] 2. For every live item write, in the user's words: WHAT breaks, WHO feels it and WHEN, what the FIX does.
- [ ] 3. Apply review.md's exposure test + the drop classes → keep / drop / Lin's call. Keep = a PR you would open today.
- [ ] 4. ONE brief for Lin for the whole batch (table per issue: item · what breaks · impact · fix · call), counts up top,
        recommendation first. Only the "What needs Lin" items are his.
- [ ] 5. Close and build per below; record the outcome on the board readme / memory.
```
A finding that cannot be stated as "a real user on path X sees Y" is a drop, however clever.

## Drop classes (each verified on board 18's 25 items)
Moot · operator-only and dry-run-visible · one operator (concurrency between two hand-run operators) · needs DB corruption
no code path writes · stacked outage (provider down across a webhook AND every retry) · already alerted or self-healing ·
cosmetic (a lost toast; billing correct either way) · manual by policy (Lin handles it by email).
**Keep:** cheap and structural (protects every user, e.g. a pooled DB connection held across a Stripe await); an input check
that turns an operator typo into a refusal; a path realistic within the product's own timeline.

## What needs Lin (everything else is yours; under full delegation inside its scope, all of it but a cross-phase move)
A product or policy call (manual vs automated, what a customer is owed, what a plan includes); a never-auto surface the fix
would touch (the triage recommends; the merge tier is his in default mode, yours under full delegation inside its scope; a
migration alone is yours in default mode since 2026-10-04 — authority.md Delegation modes); anything you cannot state an impact sentence for
but suspect matters — say "your call" with the reason, never a silent drop.

## Closing and building
- **Drop** = `gh issue close --reason "not planned"` + a comment naming each item's drop class and the reopen trigger.
- **Trim** = a comment listing the kept items; the PR's `Closes #N` closes the issue.
- **Build** = one issue's kept items as ONE PR through the normal flow; two issues never share a PR.
- **Board trap:** flipping an item to Done auto-closes its issue — triage BEFORE the Done flip and reopen any kept issue the
  flip closed (BE#660/#669).
- **Desk marker:** when a wave's residuals are triaged, update the devops WATCHES epic marker (kept items named).
