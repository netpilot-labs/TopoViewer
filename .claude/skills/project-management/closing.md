## Closing a project

Two stages, one trigger rule (Lin, 2026-07-30):

**Stage 1 — closure-ready (agent-initiated when every lane is done and verified):**
(1) all board items `Done`, every issue closed or deferred-with-named-trigger — **triage the
project's residual issues FIRST (`dev-workflow`'s `residuals.md`), then flip: when marking
Done, explicitly close and verify the item's issue; the status alone is not proof of closure,
so kept residuals must be reopened after it** (BE#660/#669,
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

Run the installed sibling `../dev-workflow/scripts/preflight.sh` from this skill directory
first (PASS/FAIL per tool, fixes nothing — Lin, 2026-10-04). Set `WORKSPACE` to the workspace
root being checked, including when invoking the canonical skill through a discovery alias.
Read the readme top-to-bottom FIRST (it is written to be sufficient), then verify its
claims against reality before acting on them: board item states, open PRs and their
latest review disposition, live flag/deploy states. The readme says what was true when
last updated; a stale readme gets corrected before new work starts, not after.

**Board mutation gotcha (2026-09-17, board 28):** `gh api graphql -F name=value` types a numeric-looking
value as a GraphQL Int — a single-select option id such as `98236657` then fails `Variable $o of type
String! was provided invalid value`. Pass ids with `-f` (always a string); `-F` only for values that must
stay typed (`-F n=28` for an `Int!`).
