---
name: dev-workflow
description: "NetPilot's mandatory development flow — how to EXECUTE work on a labeled GitHub issue: worktree → draft PR → Codex review loop → merge or hold, deploy watch, post-merge cleanup, and the always-on guardrails. Use before starting ANY code change or working ANY GitHub issue in a NetPilot repo (NetPilot-2-Backend, NetPilot-2-Frontend, netpilot-marketing, NetPilot-2-LB, containerlab-mcp, netpilot-skills)."
---

# Development workflow (executing a labeled issue)

How code work is executed. What a label MEANS is `issue-labeling`. Anything the product
agent reads (prompts, tool descriptions, deny texts) is `prompt-engineering` — load it first.
Scripts live in this skill's `scripts/`; call them by ABSOLUTE path (your cwd is a worktree) and
run them, never re-derive them. In this local workspace, use the canonical skill’s scripts at
`/Users/linzhu/agent-config/dev-workflow/scripts`. When running a generated consumer’s copy,
set `WORKSPACE` to the actual multi-repository workspace root; its location inside a component
or worktree does not identify that root. A standalone clone retains the tools but still needs
the sibling workspace and credentials for checks that require them:

| Script | Step | Does |
|---|---|---|
| `preflight.sh [--vm <name>]` | 1 | session start + every board pickup: PASS/FAIL per tool (gh scope, gcloud + IAP, db.sh, railway, env, venv, docker, `timeout`); fixes nothing |
| `pr-gates.sh <pr> --repo o/n [--watch [--wait-ci --since <t>]]` | 4, 5, 7 | both gates on the CURRENT head; `--watch` waits for the verdict; at the flip `--wait-ci --since <t>` then waits for the fresh CI run |
| `ci-wait.sh <pr> --repo o/n --since <t>` | 7 | waits for the fresh CI run, re-gates; read its `FINAL` line only |
| `pr-threads.py o/n <pr> <sha> replies.json` | 5 | replies to + resolves Codex threads by comment id |
| `merge.sh o/n <pr> [--dry-run]` | 8, 9 | base check, merge-ref check, gate, squash-merge, asserts MERGED; runs from anywhere |
| `merge-slot.sh` | 9, 10 | the per-repo merge slot `merge.sh` takes and `postmerge.sh` settles; never run by hand |
| `required-workflows.sh o/n <pr>` | 7, 8 | the workflows that must have a run on the PR's head — one definition for `pr-gates.sh`, `ci-wait.sh`, `merge.sh` |
| `postmerge.sh <repo> <merge-sha>` | 10 | Railway/Vercel deploy + health watch; exit 1 = RED · 2 = broken · 3 = REVIEW lines to attribute; a no-deploy repo gets one RESULT line |
| `redproof.sh <file> --ref <ref> \| --sub <old> <new> -- <test cmd>` | 3 | one red-proof run: green first, mutate, run bounded, always restore (test.md) |
| `with-db-lock.sh <issue-id> <cmd…>` | 3 | the local Postgres, one consumer at a time in arrival order — suite and probe runs beside sibling lanes |
| `lane-audit.sh o/n <issue>… \| -f <file>` | 11 | one row per delegated issue: state, linked PRs, merge sha, worktree left, remote branch left, slot result; exit 1 while anything is open |
| `loose-ends.sh [--mine <text>]… [--issues o/r#n…] [--project <N>] [--scratch <dir>] [--cloud]` | 11 | READ-ONLY sweep of every repo, `worktrees/`, GitHub and this machine for leftovers: one line each, ending `CLEAN` / `MINE?` / `OTHER-SESSION` / `ASK-LIN`; exit 1 = findings · 2 = a source unreadable |
| `lessons-lint.sh` | 12 | keeps these files lean: caps, tags, duplicates, dead pointers |

| Phase file | Read when |
|---|---|
| `setup.md` | creating the worktree |
| `lane-brief.md` | writing the brief for a delegated lane (the template) |
| `build.md` | before designing the change |
| `test.md` | writing tests, running local CI-parity |
| `review.md` | the Codex loop: request, watch, disposition, round cap |
| `merge.md` | ready flip, CI gate, base check, the merge itself |
| `deploy.md` | the post-merge deploy watch |
| `lanes.md` | delegating work to subagents (waiting IS a phase) |
| `shell.md` | writing any multi-step shell chain by hand |
| `screenshots.md` | a `needs/screenshots` PR |
| `residuals.md` | a residual issue: at project close, when its trigger fires, before building one |

## The flow

Copy this and tick as you go. Every code change follows it — never commit on the main checkout.

```
Dev flow:
- [ ] 0  Read the issue's agent/* label + the delegation mode in force → endpoint below (unlabeled/multiple → issue-labeling)
- [ ] 1  preflight.sh first (session start, board pickup); worktree from the remote default branch under NetPilot-Claude/worktrees/<repo>/<branch> (setup.md)
- [ ] 2  Research first, then implement; board-owned work records a stage-fit line   (build.md)
- [ ] 3  Red-proof every regression test; full local CI-parity after the LAST edit  (test.md)
- [ ] 4  Commit as lz-networks, push, DRAFT PR whose body has "Scope and accepted limits", `@codex review` + pr-gates.sh --watch (review.md)
- [ ] 5  Disposition every finding; push → re-request → re-arm; round 5 = disposition table + decision in ONE comment, no round 6 without it (review.md)
- [ ] 6  Guardrail check on the actual DIFF: a never-auto surface demotes to agent/hold (default mode)
- [ ] 7  merge.sh --dry-run (main moved → rebase, re-verify, dry-run again) → gh pr ready → explicit `@codex review` → ci-wait.sh --since <t> (no-CI repo: pr-gates.sh) (merge.md)
- [ ] 8  merge.sh --dry-run: base check + merge-ref + gates read; main moved → rebase + re-verify (merge.md)
- [ ] 9  Endpoint: auto = merge.sh (runs from anywhere) · hold = PR-ready report, stop (full delegation in scope: merge.sh)
- [ ] 10 postmerge.sh <repo> <merge-sha> (every repo; a no-deploy repo then does its own step, deploy.md); exit 1 → impact decides: outage or many users = roll back, else fix forward (deploy.md)
- [ ] 11 Cleanup: pull main, remove worktree, delete branches (+ screenshots ref), board rows; delegated lanes → lane-audit.sh;
         then loose-ends.sh — every finding is cleaned up, closed out, or raised to Lin
- [ ] 12 Learning pass (skill-maintenance); lessons-lint.sh if this skill changed; last PR comment `learning-pass: <sha>|none (why)`
```

Step notes:
- **2** Confirm the issue is not already done. Prefer a built-in or official pattern over
  hand-rolling; frontend UI diffs check the installed upstream provider's src first
  (`feature-research` owns the method). New packages: latest stable, pinned.
- **4** Draft pushes skip every CI job on the four main repos, so Codex rounds run CI-free;
  the one real CI run is step 7. On Frontend/Marketing every branch commit must be AUTHORED
  `lz-networks` or Vercel blocks the production deploy (merge.md). PR labels follow the
  OWNER: a session-owned PR stays UNLABELED with any hold stated in the body; a loop-owned
  PR mirrors the issue's `agent/*` (+ `needs/*`) and adds `origin/devops`. **A PR with no
  issue IS a session-owned PR**: its endpoint comes from the delegation mode in force (below)
  and its body states the authority line (Lin, 2026-10-04).
- **The two gates, and the only two:** CI green = the NAMED required checks reporting
  `success` on the CURRENT head (absent is not green, a draft run is not the gate, ignore
  the `Vercel` check); Codex dispositioned = a verdict on the CURRENT head with every
  finding fixed / accepted as residual / deferred / routed (acceptable risk, never zero
  findings). `pr-gates.sh <pr> --repo o/n` answers both; READY means dispositioned, so read
  the verdict's substance. There is no branch protection — you are the gate.
- **11** `git checkout main && git pull --ff-only` in the main checkout; `git worktree remove --force <path>`; delete the branch
  locally and remotely, plus `refs/heads/screenshots/<issue>` on a screenshots PR. Prune other merged branches by SHA only
  (tip == a merged PR's `headRefOid`, or `ahead_by == 0`), never `main`, an open-PR branch or a checked-out one. Board-owned
  work updates the readme rows and the project folder's INFLIGHT (agent repos) NOW, not at stage end.
- **Loose ends — the last act of ANY agent-led work** (a PR, a lane wave, a project close; Lin, 2026-10-05): run
  `loose-ends.sh --mine <your branch or PR>` (a coordinator: ONCE for all its lanes, after `lane-audit.sh`; `--project <N>` /
  `--issues` at a board close, `--scratch <dir>` always, `--cloud` after image or fleet work). Every line it prints gets exactly
  ONE outcome — cleaned up, closed out, or RAISED to Lin in the final message with a one-line recommendation; nothing stays
  that Lin does not know about. A session that stops earlier (an `agent/hold` PR-ready report, a blocked lane) runs it before
  its final message and reports its own open PR and worktree as held. An `OTHER-SESSION` line is never touched: report it as "other session's, left alone".
  Irreversible cleanups (dropping a stash, deleting unmerged work, deleting a cloud resource, killing a process you did not
  start) are Lin's call unless the delegation mode in force covers them. Exit 2 is not a clean sweep — say what was unreadable.
- **Stage-fit (board-owned work):** one line at PR-open and again at merge — "Stage-fit:
  within <wave> per <readme> because …" — judged on the DIFF, not the issue text. Out of
  stage → shrink the PR or raise the cross-stage question (`project-management`).

## Delegation modes (Lin, 2026-10-04 — two, nothing in between)

- **Default mode** (no explicit delegation): the agent handles low-risk PRs AND database
  migrations end to end — `agent/auto` work, plus migrations under the HOW rules in merge.md
  (additive applied to Neon before merge; destructive = expand → deploy → contract) — and leaves
  to Lin any PR that carries risk or a product decision: the never-auto list below minus
  migrations stays `agent/hold`. Migrations moved from never-auto to default-mode auto on
  2026-10-04 (Lin): an older migration issue still labeled `hold` is relabeled `auto` at pickup
  when its diff is a migration alone.
- **Full delegation** — Lin's words: *"if I say this, I expect the agent to make its own best
  decisions and handle everything end to end including merge PR, db migration, and all the
  other permissions that complete the task/project that I defined."* Every endpoint is
  merge-and-finish within the task/project he defined — guardrail surfaces, image promotion,
  fleet sweep, admin DB writes on the `db-access` allowlist included (off it stays a code change). Each PR body records it: `Delegation: full, Lin <date>,
  scope: <task/project>`. It still stops for what lies outside the defined task/project (a cross-phase
  scope move changes what he defined — `project-management`) and for what no mode covers: a reviewer outage, Stripe/billing amounts, anything irreversible outside
  the task. An `agent/stop` item inside the scope is worked: the agent takes the decision it was
  waiting for, records it on the issue (options + pick + why) and relabels before any code; a
  design or phase parent stays `stop` (worked via its sub-issues). Closing the BOARD stays his
  trigger (`project-management` Stage 2): the agent reaches closure-ready and asks once. The two
  gates and the HOW rules (migration ordering, the customer-VM script rule below, red-proofing)
  never lift.
- **An item inside a question just put to Lin waits for his answer, whatever its label**
  (Lin, 2026-10-02: "don't start work before I answer").

## Endpoints by label

- **`agent/auto`** — merge yourself after step 8, watch the deploy, clean up. At the round
  cap, merge-and-accept is legitimate when the residual fails its exposure test; drop to
  `agent/hold` only if the call genuinely needs Lin. Do not involve Lin unless something fails.
- **`agent/hold`** — stop at PR-ready (CI green + verdict on the CURRENT head + every finding
  dispositioned; a pending re-review is in-flight, not ready). Never enable auto-merge. Post:
  PR link, 2–4 line summary, exactly what Lin should test or eyeball, dismissed findings with
  one-line rationales. Merge only under full delegation or if Lin says so in the current
  conversation, then step 10–12; the base check applies with near certainty. **Feature builds
  and agent-behavior work under either grant — full delegation or a one-off merge say-so** (Lin, 2026-08-04): ship the product test WITH the feature in
  `NetPilot-2-Backend/tests/product/<feature>/` (PROMPT.md / VERIFY.md / probe; contract in its
  README — a judge agent grades behavior, never keyword matching), verify it yourself by RUNNING
  it (headless production turns: `probe-testing`), and hand Lin only an eyeball list plus the verified prompts. Then reconcile
  the run — HIS under a one-off grant, your OWN under full delegation — scorecard × VERIFY.md queries × UI claims — and feed
  every mismatch back into the feature before closing.
  Merges are delegated, `needs/screenshots` included (screenshots still attached as evidence).
- **`agent/stop`** — no worktree, branch, PR or code. Allowed: read-only investigation and one
  issue comment with 2–4 options and a recommendation. Code starts after Lin picks and tiers —
  or, under full delegation and inside its scope, after the agent's recorded decision (above).

## Duty flags

- `needs/drain-test` → kick off a long lab request just before the deploy, confirm the ~300 s
  drain lets it finish, verify `/health`.
- `needs/screenshots` → before/after frames + a click-through in the PR report
  (`screenshots.md`); never self-merged (it is `agent/hold`) except under either grant above — full delegation or
  Lin's one-off say-so.
- `p1 | p2 | p3` → sequencing only. Unblocked issues run in PARALLEL by default — several PRs in flight in one repo
  included (Lin, 2026-10-01, replaces "at most one `agent/auto` PR in flight per repo"; board 31's feedback lane). Only the
  MERGES queue: `merge.sh` holds the repo's merge slot until that merge's `postmerge.sh` ends clean, so a sibling's
  `merge.sh` answers NOT MERGED meanwhile and then meets step 8's base check (main moved → rebase + re-verify; merge.md).
  Two issues that edit the same file are not parallel (`project-management`'s parallel-lane analysis).
- A duty you cannot fully exercise: do the nearest verification and SAY so.

## Guardrails (always on — a diff can demote a label; a label never lifts these; the never-auto list opens only to the two carve-outs below, to Lin's one-off say-so in the current conversation, and to full delegation inside its scope)

- **Never-auto list — in default mode never self-merge a diff that touches:** auth
  (Clerk/JWT/JWKS/session/sign-out) · billing (Stripe/webhooks/tiers/cost recording/reconciler) ·
  VM lifecycle (Pulumi/GCP/Cloudflare/golden images/any destroy path) · anything in NetPilot-2-LB ·
  env or secrets · CI/workflow files · agent-governance files (`CLAUDE.md`, `AGENTS.md`, `.claude/`, `.agents/`,
  `DISALLOWED_TOOLS`) · a semver-major dependency upgrade · any Claude Agent SDK version change.
  DB migrations left this list on 2026-10-04 (Delegation modes). Diff-detected: demote yourself
  to `agent/hold` and name the class, even on a mislabeled issue.
- **A script that touches customer VMs or production data runs only from a reviewed, MERGED
  revision** (an urgent fix, or an additive/data migration applied before merge per merge.md: at
  least a Codex-clean head); a customer-VM or fleet script runs on the canary — Lin's own `linzhu-vm`
  — before the fleet (a migration's verification path is merge.md's, not a canary host) (Lin, 2026-10-04: the 0.3.36 sweep ran an unreviewed branch on 39 VMs; review
  then found 8 rounds of real edge cases, one of which had already stopped a VM mid-install —
  skills PR#59). Both modes.
- **Dependency-bump carve-out** (Lin, 2026-09-09): a diff that is ONLY a dependency bump on one
  of these surfaces follows `dependency-updates` tiers (T4 heavy gate merges; T5 holds).
- **Low-risk carve-out** (Lin, 2026-07-30): a guarded-surface diff may self-merge only when ALL
  FOUR hold — (1) risk ≤ 25 AND confidence ≥ 85 scored on the diff (15 until Lin, 2026-10-05: BE PR#969, a one-value
  retry-set fix scored 20, waited three days for his merge); (2) no semantic change to
  the guarded surface: observability-only lines, or a narrow pure-helper bug fix whose tests fail
  without it; (3) not hard-core — billing logic/amounts · env/secrets · CI/workflow files ·
  governance files (except the fact line below) · semver-major · Agent SDK are never self-merged
  in default mode, no scores; (4) CI + Codex clean, mandatory deploy watch, an FYI record naming
  the shape.
- **Fact-based CLAUDE.md line** (Lin, 2026-09-04): a repo or root CLAUDE.md line recording a
  verified fact or evidenced footgun may be written and self-merged. Collect them in ONE
  `agent/auto` docs issue per repo and land LAST as one PR; re-verify every collected line
  before landing by RUNNING what it claims, not only reading the code (2 of 3 needed correction, BE PR#748;
  4 of 6, three visible only in a run, clab PR#265), and grep the repo for `CLAUDE.md` pointers before
  renaming a section; state only the scope you
  verified — universal quantifiers ("never", "the only") are where every Codex precision finding
  lands (FE PR#536/#541, BE PR#842). Policy or preference changes to governance files stay Lin's in default mode.
- **Never self-merge a PR that weakens, skips or deletes tests/checks or lowers coverage** —
  automatic `agent/hold`, in both modes, unless that test change IS the defined task.
- Scope larger or different than the issue → `agent/hold` with the delta explained.
- Cross-repo work = one PR per repo, each under that repo's own issue label.
- Risk acceptance disposes of FINDINGS; it never moves a merge gate — not for a never-auto
  surface, not for CI-gaming, and never for a Codex outage (reviewer outages are always Lin's).
