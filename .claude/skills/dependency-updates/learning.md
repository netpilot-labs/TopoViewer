# The learning pass — how this skill improves after every pass

**Contents:** 1 When and the rubric · 2 Placement (which file owns what) · 3 Self-serve vs
Lin · 4 Demotion, promotion, pruning · 5 Evals · 6 Run-report exemplar.

The pass is step 8 of the checklist — it runs BEFORE the report so the report cites what
changed, and it runs on every pass, including a pass that merged nothing (Lin,
2026-09-08 on `probe-testing`: "learn during the loop"). It is the `skill-maintenance`
learning pass specialized to this skill; that skill's earned-content test and charter
apply to every line written here.

## 1. The rubric — answer each line, in order

```
Learning pass:
- [ ] a. OUTCOMES — every item handled has an outcome (merged-clean / reverted / held /
        blocked / dismissed / red-diagnosed / red-superseded / handed-off) and the ledger
        row that reflects it (trust count, watch flag, trigger stamp, dismissal row).
- [ ] b. PROCEDURE DEFECTS — any step where this skill's text OR a script was wrong,
        missing, or ambiguous (a command failed, a script printed a false FINDING or
        missed one, a check was skipped because it was unclear, a tier was mis-assigned,
        a signal was read too late). Fix the line or the script NOW, with provenance
        (PR/alert/pass id + date); `bash -n` every edited script and re-run it on the
        case that exposed it. Self-serve.
- [ ] c. NEW FOOTGUN — something reproducible that cost time and is not derivable on the
        spot → gotchas.md under its surface. Grep first; update an existing line rather
        than add a sibling.
- [ ] d. AUDIT NOTES — every package audited this pass has its ledger audit notes
        refreshed (what we use → what to read). This is the compounding asset: audits
        start ahead next time.
- [ ] e. INCIDENT — a revert or a red post-merge signal → incident row, package onto the
        watch list, the catching signal into mechanics §8 if new, and the lesson placed
        (§2). Demotion is immediate and self-serve.
- [ ] f. POLICY SIGNAL — a boundary that keeps producing the same outcome (holds Lin
        merges unchanged ≥3×; a tier that let something through) → a proposal row with
        the evidence links. Never self-applied.
- [ ] g. EVALS — did a case this pass expose a gap the evals (§5) would not have caught?
        Add or replace one (cap 6).
- [ ] h. PRUNE (every ~10 passes, count in the snapshot) — re-verify each gotcha still
        reproduces, drop stale trust rows, keep the incident log at 10, re-read SKILL.md
        against skill-maintenance's format rules, run every script once against the live
        inventory (a script nobody ran in 10 passes is either dead or untested).
- [ ] i. SHIP — canonical-source worktree: commit (message names the pass and lesson),
        then complete `dev-workflow` through the reviewed source merge. Run `sync-all.sh`
        after that merge; ship generated consumer updates through their reviewed PRs.
        Owned worktrees finish clean; report any held source or consumer PR explicitly.
```

A pass that changed no durable file is the exception, and the report says so
explicitly ("learning pass: nothing durable").

## 2. Placement — which file owns what

| Lesson shape | Goes to |
|---|---|
| A gate, an always-on rule, the checklist order | `SKILL.md` (only if load-bearing on the spot; else a pointer) |
| A tier boundary, an endpoint, a never-auto mapping | `tiers.md` — §6 if it needs Lin, §1–§5 once ratified |
| A deterministic step (inventory, diff, check, state change) | `scripts/<name>.sh` — and its row in the `mechanics.md` table |
| A judgment step's method, a signal to read, a command with no script yet | `mechanics.md` |
| A reproducible trap with its symptom and cause | `gotchas.md` |
| Per-package knowledge, triggers, dismissals, incidents, counts | the ledger (`netpilot-devops/ledgers/dependency-updates.md`) |
| A rule about how this skill learns | this file |
| A rule about EXECUTING any PR (gates, merge mechanics, worktrees) | `dev-workflow` — never restated here |
| A Renovate/Dependabot fact true for ONE repo only | that repo's `CLAUDE.md` |
| The story behind a rule (why, who, how it felt) | memory, not the skill |

## 3. Self-serve vs Lin (the `skill-maintenance` charter applied)

**Nothing about this skill's shape is fixed** (Lin, 2026-09-08): the files, scripts, and
sections that exist today are the seed. A pass may add, merge, split, shrink, or delete
reference files and scripts — and rewrite SKILL.md's procedure — when the change is
grounded in real work or a human direction and wins on the three criteria, in this
order: **better outcome** (fewer misses, fewer wrong tiers), **less production risk**,
**a cheaper pass**. Two constraints stay: `skill-maintenance`'s format rules (fetch the
live authoring guidance before a restructure; SKILL.md under ~500 lines; references one
level deep; earned content only) and the tier below — autonomy boundaries never move
without Lin.

- **Self-serve, same pass:** procedure defects, footguns, audit notes, trigger stamps,
  watch list demotions, incident rows, evidence-based qualifications of a rule (the
  evidence cited in the edit), consolidation and pruning, and the restructuring above
  (say what moved and why in the report).
- **Lin, via a proposal row + desk line:** any change to a tier's endpoint, the never-auto
  list, cadence, dismissal authority, the auto-revert grant, labeling of bot PRs — every
  expansion of what the pass may do alone, however small. Evidence contradicting one of
  his rulings is a question, never an overwrite.
- **Unsure which:** it is a question.

## 4. Demotion, promotion, pruning

- **Demotion** (self-serve): incident → watch list, immediately. The watch flag holds T3
  bumps of that package until 3 consecutive clean merges; T2 bumps stay self-merge with
  the incident's signal re-read post-merge.
- **Promotion** (Lin): the ledger counts; the learning pass files the proposal when a
  package or boundary reaches 3 unchanged Lin-merges; nothing moves until his reply.
- **Pruning:** a gotcha whose failure has not reproduced across ~10 passes is deleted
  (the vendor-guide rule, `add-vendor` 1-i); a trust row with no activity in 6 months is
  deleted; proposals Lin dropped are deleted with the reason noted in the tiers §6 line
  they replaced (one sentence, then nothing).

## 5. Evals — would the skill, read cold, get these right? (seeded 2026-09-08 from live cases)

Run mentally when rewriting any file; run for real (a scratch dry-run of steps 0–3 on the
live inventory) after a structural edit.

1. **Green grouped runtime PR, 3 weeks old, no reviews** (BE#507: alembic minor,
   sqlalchemy patch, sse-starlette patch, svix minor, uvicorn patch). Expected: tier T3
   (highest member), `svix` recognized as T4 billing-adjacent → split out; `uvicorn`
   carries `needs/drain-test`; audit lines per package on the PR; Codex requested;
   endpoint per tiers §1 (T3 self-merge when the audit is clean); the 22-day age reported
   as a finding.
2. **High alert blocked by an upstream cap whose trigger has fired** (BE#29 / BE#382:
   clerk-backend-api 7.0.0 lifts `cryptography` to `<51`). Expected: step 2 detects the
   fired trigger before any PR work; the fix is a T4 major of a dev dep → PR-ready with
   the real-Clerk suite run locally, verdict on the desk, BE#382 updated; never a
   forced `cryptography` override under 6.0.1.
3. **Red automerge-tier PR while `main` is green** (FE#337 with sibling #338, identical
   `ERR_INVALID_URL_SCHEME`). Expected: lockfile diff of both branches vs main, the
   shared unlisted transitives named as suspects, bisect by pinning one at a time on one
   failing suite, culprit reported on the PR; never a test edit; gotchas §2 line replaced
   with the answer.
4. **Transitive-only alert with no Renovate PR** (BE#30 pip under pip-audit; FE#77
   js-yaml under eslint — the first pass, 2026-09-09). Expected: ladder step 2, the
   surgical bump (`uv lock --upgrade-package pip` / override key refreshed in place +
   `pnpm install --lockfile-only`), dev-only exposure → T1 endpoint, the cooldown checked
   on the version the lock RESOLVED (a caret lands the newest in-range release, not the
   alert's patched one), a diff of exactly the lockfile (+ manifest for pnpm), alert
   closes on the next scan (verify against the lockfile, not the alert list).
5. **Dashboard approval for a runtime image major** (postgres 18). Expected: Neon major
   read via `db-access` (17), approval NOT ticked, the CI service's lag behind prod (16
   vs 17) reported as the real drift.

## 6. Run-report exemplar (one shape; replace, never accumulate)

```
Dependency pass 3 — 2026-09-09 12:40–13:35Z, attended; Lin 12:40Z: T4 is mine too, he takes
  decisions and major breaks only (tiers §6). Ten PRs that pass 2 had parked for his click.
Fleet: alerts 1/4/4/0 → 0/0/0/0 · Renovate PRs 10 → 3 (marketing majors parked on upstream).
Merged (self, every watch clean, 60-min sweeps at 13:50Z + 14:35Z): FE #486 next 16.3.4 (4 crit) ·
  MKT #176 next 16.3.4 (4 crit) · BE #744 clerk-backend-api 7 + cryptography 50 (real-Clerk local
  55/55, main run green, prod /api/v1 traffic 200s, no jwt/jwks errors) · BE #741 postgres-17 CI ·
  BE #578 setup-uv v10 · BE #747 svix 2.2.0 (hand; §3 probe: sign+verify round trip; 120/120 webhook
  suites; superseded #507) · FE #470 setup-node v7 · FE #495 posthog-js 1.425.0 + sentry hold
  <10.69.0 + exact pin (hand; superseded #338 whose lock had 10.72.0 → 122 red) · clab #64/#65/#66.
Held for Lin (T5): none. BE#742 decided 2026-09-10: (b) status quo. Do NOT: postgres 18.
Watch rows opened: svix first Clerk delivery 200; clab actions at next cloud-v* tag; sentry trigger 10.74+.
Learning pass: tiers §1/§2 rewritten (T4 heavy-gate + risk split + surfaces' own checks, T5 decision
  test, watched package ≠ hold); scripts/merge.sh (base check → gate → merge → watch, main(); 11 merges);
  gotchas: `| tail` hides a spawn failure, macOS has no `timeout`, sentry 10.72 + exact-pin reason,
  lockdiff needs a committed ref; dev-workflow Guardrails dependency-bump carve-out; ledger rows ×8.
Gap to raise once: PostHog capture signal needs an API key in netpilot-devops/.env.
Canonical source: PR <n> merged at <sha>; affected consumers: <PR/status>, or no generated change.
```
