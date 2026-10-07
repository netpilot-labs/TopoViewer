---
name: project-management
description: Runs a multi-issue initiative as a GitHub Project — when to create a board, the readme contract, issue/PR linking, the status discipline, scope discipline, and project closure. Use when work spans multiple issues, PRs, or repos, when creating or updating a GitHub Project board, or when picking up an existing one.

---

# Project Management (multi-issue initiatives)

A GitHub Project is the coordination layer for any initiative too big for one issue:
multiple PRs, multiple repos, ordered waves, or work spanning multiple sessions/agents.
The board — and above all its **readme** — is the single handoff-ready source of truth:
any agent (or Lin) must be able to read it top-to-bottom and know exactly what is live,
what is in flight, what is blocked on what, and what to do next.

## When to create a project

Create one when work will span **3+ issues, 2+ repos, or 2+ sessions**, or has ordered
phases where sequencing mistakes are expensive (deploy-order dependencies, flag flips,
migrations). One-issue work never gets a project. Ask Lin before creating a project for
a NEW initiative he hasn't scoped; converting his existing plan into a board is routine.

## Setup mechanics

```bash
gh project create --owner lz-networks --title "<initiative name>"
gh project edit <N> --owner lz-networks --readme "$(cat readme.md)"   # readme = contract below
gh project item-add <N> --owner lz-networks --url <issue-url>          # every related issue
```

- Requires the `project` token scope (`gh auth refresh -s project` if missing).
- Issues are created per the **issue-labeling** skill (taxonomy, sub-issues, labels) in
  their own repos, then added to the board. Every issue body links back to the umbrella
  issue AND the project URL so navigation works from any entry point.
- **The design issue is board item #1 and the project's guide** (Lin, 2026-08-30 —
  replaced the umbrella-issue + flat-sub-issue shape; first practiced on Team Plan
  board #18). It never has a PR of its own; it holds the architecture, the probe
  findings, and the decisions-with-rationale, and it is a LIVING document: when
  implementation contradicts or refines the design, update it in the same breath as
  the code PR (a stale design misleads every later phase). There is NO separate
  umbrella/tracking issue — the design issue is the navigation hub every other
  issue links back to. The readme stays a STATUS doc and links to the design issue
  rather than restating it.
- **Work is grouped into PHASE issues** — one issue per execution phase, titled
  `Phase <n> — <name>`. Phases that run in parallel are lettered siblings
  (`Phase 2a — …`, `Phase 2b — …`): the letter IS the parallel-lane claim, and the
  readme's parallel-lane analysis (contract §4) is the evidence behind it, written
  at scoping time. Each phase issue is a **parent whose PR-sized units are its
  sub-issues** (created and labeled per `issue-labeling`; cross-repo allowed; slice
  for disjoint file sets so a phase can fan out to multiple agents). A single-unit
  phase skips the parent — one plain issue carrying the phase title. **Two levels
  max** (phase → PR unit): deeper nesting gets lost in partial reads and the UI.
- **Phase issue body**: the phase goal, its sub-issue checklist with intra-phase
  ordering + blockers ("blocked by" stated explicitly — GitHub's own best-practice
  guidance), the phase NOT-list, and links to the design issue + project URL.
  Phase parents are `agent/stop` (worked via their sub-issues); a phase closes when
  its last sub-issue closes and its verification passed.
- **Board membership**: design issue + all phase issues + all sub-issues. Group the
  default board view by **Parent issue** so phases read as sections; the parent
  item's sub-issue progress bar is the phase roll-up.
- **Every PR carries a real `Closes #NN`** targeting its PR-sized sub-issue — "Part of
  #NN" is prose GitHub ignores: no Development-panel link, no auto-close (BE PR#222,
  2026-07-24). When one sub-issue turns out to need multiple PRs mid-flight, split it
  into sibling sub-issues under the same phase on the spot (BE#223 pattern) instead of
  shipping a keyword-less PR. The board shows PRs via the issue's linked-PR field —
  do not add PRs as separate board items.

## The readme contract

The readme is a **status document, not a design doc** (designs live in the dedicated
design issue(s) above; code is truth). Required sections, in order:

1. **Goal** — 2-4 sentences: what this delivers when done. Link the umbrella issue.
2. **Current state table** — one row per shipped/live/dormant piece: what it is, its
   exact state (merged/deployed/flagged-off/soaking/held), and the verifying evidence.
3. **Shipped log** — merged PRs with one-line summaries and review-loop notes worth
   keeping (round counts, key dismissals, wire facts discovered).
4. **Execution order from HERE** — the remaining work listed by the board's phase
   issues (`Phase 1`, `Phase 2a/2b`, …), with an explicit **parallel-lane analysis**.
   The point of lettered phases is fan-out: each lettered sibling (and each sub-issue
   inside a phase with disjoint files) can be assigned to a DIFFERENT agent at the
   same time — so don't just order the steps, reason about independence and write
   the conclusion down:
   - **parallel lanes**: per phase, name which phases/sub-issues run simultaneously
     (one agent per issue) and the EVIDENCE they can't collide — disjoint file sets,
     different repos/surfaces, no shared state, or both landing dormant until a later
     integration step. Two issues that edit the same file are NOT parallel —
     sequence them (ordering is cheaper than a rebase war). Say it explicitly
     either way; silence reads as "sequential";
   - **blockers**: what must land first and WHY (the failure if ordered wrong);
   - **per-phase NOT-lists**: each phase line names what it deliberately does NOT
     ship ("Phase 2 ships files/; NOT artifacts, NOT memory") — the scope-discipline
     rules above need something concrete to check against, and most creep is a
     missing non-goal, not a bad decision;
   - strike through (`~~...~~`) completed steps with the completion date — never
     delete them; the trail is how a later reader trusts the doc.
5. **Pending on Lin** — the decisions/verifications only he can do, each one concrete.
6. **Watch-items** — accepted risks and interim regressions with their planned fix
   location, so nobody re-reports them as new bugs.

## Scope discipline — intent must not drift between the plan and the work items

A mid-project issue authored in the code-reviewer's frame put Stage-3 scope into a
Stage-2 PR, and every downstream gate faithfully executed the drifted text (BE#320,
2026-08-01 — full story in memory). The gap was one unnamed moment: **minting a work
item mid-project.** These rules name it.

1. **Every issue or scope expansion minted MID-PROJECT names its phase.** The issue
   body carries its phase (linking the parent phase issue) and ONE line: *"In-phase
   because …"*. Work that cannot name its phase does not get filed — it gets a plan
   row first (which forces the phase question into the open), or routes to the future
   phase's issue as an inherited-scope comment. An issue with no phase assignment is a
   drift alarm by construction.
2. **Two kinds of drift, two lanes** (Lin, 2026-08-01):
   - **In-stage design change** — implementation proved the design wrong, or found a
     cleaner way, *within what the current stage ships*: **self-serve**, but document it
     in the SAME BREATH as the code — decisions-ledger row + readme execution-order edit +
     desk/report FYI. Undocumented is indistinguishable from unintended.
   - **Cross-phase scope move** — work migrating between phases, or a change to what
     a phase SHIPS: **never self-serve**, regardless of how technically compelling.
     Phase boundaries encode the owner's risk sequencing (deploy order, flag flips,
     migrations); surface it as a question with a recommendation and wait. "The premise
     spans both surfaces" is an argument to RAISE, not a license to build.
3. **Reviewer framing is not plan framing.** A code reviewer scopes findings by code
   truth, never by plan-fit — issues and fixes derived from review findings are the
   highest-drift-risk items and get rule 1 applied most strictly.

## The status discipline (the part that decays if not enforced)

Status lives in FOUR places — the readme and the status-update feed are BOTH
first-class as the project progresses (the readme is the always-current truth you
rewrite in place; status updates are the append-only dated feed you never edit):

1. **Item status** on the board (`Todo` / `In Progress` / `Done`):
   ```bash
   gh project item-edit --id <item-id> --project-id <proj-id> \
     --field-id <status-field-id> --single-select-option-id <option-id>
   ```
   Flip to In Progress when a PR opens (or work genuinely starts), Done only when
   merged AND its deploy/verification step passed.
2. **The readme** — every state change rewrites the affected rows/steps: a flag flip,
   a soak result, a PR entering review, a hold, a discovered blocker, an interim
   regression. Date every claim (`verified 2026-07-23`). While WAITING on something
   (review verdict, deploy, Lin), record the wait itself: what is pending, since when,
   what unblocks it — so an interrupted session loses nothing.
   **`--readme` replaces the WHOLE document, and every parallel lane on the board writes
   it** — fetch it fresh INSIDE the script that edits it, anchor each edit on that fetch
   (`assert count == 1`; never on a read from earlier in the session), write, then re-read
   and confirm your row AND the sibling lanes' rows survived. A clobbered row reads as
   "that lane never updated the readme", not as an overwrite (board 24, 2026-09-13: three
   lanes merged within minutes; a session-start anchor missed after a sibling's rewrite —
   the assert caught it).
3. **The issue/PR** — the detailed trail per dev-workflow (PR-ready reports, review
   dispositions, inherited-scope comments).
4. **The status-update feed** — post a native project Status Update at every
   meaningful progress point AS the project runs, not only at the end: wave
   done, flag flipped, PR entering/leaving review, blocker discovered, loop
   closed, incident. It gives Lin a dated ON_TRACK/AT_RISK narrative without
   diffing the readme. No gh subcommand exists; use GraphQL:
   ```bash
   gh api graphql -f query='mutation($p:ID!,$b:String!){
     createProjectV2StatusUpdate(input:{projectId:$p,status:ON_TRACK,body:$b})
     {statusUpdate{id}}}' -f p="$(gh project view <N> --owner lz-networks \
     --format json --jq .id)" -f b="<markdown body>"
   ```
   (status: ON_TRACK | AT_RISK | OFF_TRACK | COMPLETE | INACTIVE). Keep it to one
   paragraph of what shipped/changed + one of what's next/pending — the readme
   holds the detail.

Deferring work discovered mid-project? It must land as a comment on the issue that
will own it (inherited-scope pattern) AND a readme watch-item — "we'll remember" is
not a mechanism; items that live only in chat are lost.

## Boy-scout modularity rule (refactor rides on project work, never alone)

When scoping a project's implementation issues, check whether the files each wave
touches are oversized (guideline: >1,000 lines backend / >800 frontend, excluding
vendored and data-only modules). If so, plan a **behavior-preserving split as that
wave's lead-off PR** — split first (a reviewable move-only diff, public imports kept
stable via package/module re-exports), then land the feature in the new modules.
Rationale: big files serialize parallel work and degrade review quality, but
standalone refactor campaigns cost a full review loop with no feature payoff — so
the split only happens where a project is already paying for the review. Dedicated
refactor issues were retired (BE#208 / FE#162, 2026-07-24; their file inventories
remain the reference list of known oversized files).

## Cross-project boundaries (comment-only on what you don't own)

A session OPERATES only the artifacts of the project it is running. An issue or PR
belonging to another project/board — or any session-owned PR (unlabeled, hold
stated in body) — is **read-only except for comments**: post your findings, triage,
or coordination notes on it and **alert Lin**; never label it, push to its branch,
resolve its threads, re-request its reviews, or merge it. This holds even when your
project DEPENDS on it (Lin's rule, 2026-07-24; FE#178). Ask the ownership question
BEFORE acting, not after; an explicit in-conversation delegation from Lin is the
only override. Handle the dependency itself by recording it on BOTH boards
(readme + status update) and letting each owner drive its own lane. Discovering
your PR is stacked on a foreign branch is a dependency to document — not a license
to operate the base.

## Closing a project

Two stages, one trigger rule (Lin, 2026-07-30):

**Stage 1 — closure-ready (agent-initiated when every lane is done and verified):**
(1) all board items `Done`, every issue closed or deferred-with-named-trigger — **triage the
project's residual issues FIRST (`dev-workflow`'s `residuals.md`), then flip: a Done flip
auto-closes the item's issue, so kept residuals must be reopened after it** (BE#660/#669,
2026-09-05);
(2) rewrite the readme as an **archived status doc** — "PROJECT COMPLETE <date>" header,
final prod state, shipped log, **standing decisions** (the accepted policy defaults and
dismissed residuals, so nobody re-litigates them), and watch-items that outlive the
project; (3) post a final `COMPLETE` status update; (4) `dev-workflow`'s loose-ends sweep (its step 11, `--project <N>`); (5) report closure-ready on the desk.

**Close steps that need Lin go to him as ONE plan, once** — the remaining sequence, each
trade-off stated once, and one ask naming every action only he can authorize (a release cut, a
customer-facing sweep, a production DB write — in default mode; under full delegation inside its scope the agent
takes those and asks once only for the board close, `dev-workflow` Delegation modes) — never "waiting for Lin's go" step by step, and
never a list handed over for him to triage: what the data settles is already done or filed
(board 31, 2026-10-01: three rulings on one sequence in a day; `add-vendor` Project close is
the worked order).

**Stage 2 — full closure. Trigger: Lin says "close project <X>" (in any words) — that IS
the authorization; execute ALL of it, no further asks:**
1. Verify Stage 1 actually holds (finish any gap first — never close over open lanes).
2. `gh project close <N> --owner lz-networks` (verify `.closed == true`).
3. **Dev project folder** (agent repos with `projects/<slug>/`): stamp PLAN.md with a
   `> PROJECT CLOSED <date>` header block, write a FINAL HANDOFF worklog entry (outliving
   items + as-of SHAs), INFLIGHT terminal. The folder stays as the engineering archive.
4. **Desk cleanup**: the project leaves the desk ENTIRELY — no FYI line either (Lin ordered
   the closure; the folder's final handoff + the board readme are the record, and anything
   that guides future work goes to a skill or CLAUDE.md). DEFERRED keeps only outliving
   triggers that have no other single source.
5. Memory/worklog note per `skill-maintenance`'s post-merge pass.

Never close a board Lin has not told to close; never leave one half-closed (board closed
but desk/folder still live, or vice versa).

## Picking up an existing project

Run `/Users/linzhu/git_projects/NetPilot-Claude/.claude/skills/dev-workflow/scripts/preflight.sh` first (PASS/FAIL per
tool, fixes nothing — Lin, 2026-10-04).
Read the readme top-to-bottom FIRST (it is written to be sufficient), then verify its
claims against reality before acting on them: board item states, open PRs and their
latest review disposition, live flag/deploy states. The readme says what was true when
last updated; a stale readme gets corrected before new work starts, not after.

**Board mutation gotcha (2026-09-17, board 28):** `gh api graphql -F name=value` types a numeric-looking
value as a GraphQL Int — a single-select option id such as `98236657` then fails `Variable $o of type
String! was provided invalid value`. Pass ids with `-f` (always a string); `-F` only for values that must
stay typed (`-F n=28` for an `Int!`).
