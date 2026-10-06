---
name: dev-workflow
description: "NetPilot's mandatory development flow — how to EXECUTE work on a labeled GitHub issue: worktree → draft PR → Codex review loop → merge or hold, deploy watch, post-merge cleanup, and the always-on guardrails. Use before starting ANY code change or working ANY GitHub issue in a NetPilot repo (product, tooling and agent configuration repositories, including TopoViewer and the agent desks)."
---

# Development workflow (executing a labeled issue)

Read [authority.md](authority.md) before choosing a lane, delegating work, editing a guarded
surface or approving a merge; it owns delegation modes, endpoints, duty flags and always-on
guardrails.

How code work is executed. What a label MEANS is `issue-labeling`. Anything the product
agent reads (prompts, tool descriptions, deny texts) is `prompt-engineering` — load it first.
Scripts live in this skill's `scripts/`; call them by ABSOLUTE path (your cwd is a worktree) and
run them, never re-derive them. For canonical and generated scripts, set `WORKSPACE` to the
actual multi-repository workspace root (locally `/Users/linzhu/git_projects/NetPilot-Claude`).
Use the canonical scripts at `/Users/linzhu/agent-config/dev-workflow/scripts` in this local
workspace. Their convenience link and a generated copy’s component/worktree location do not
identify the workspace root. Standalone clones still need the sibling workspace and credentials
for checks that require them:

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
- [ ] 7  gh pr ready → explicit `@codex review` → ci-wait.sh --since <t> (no-CI repo: pr-gates.sh) (merge.md)
- [ ] 8  merge.sh --dry-run: base check + merge-ref + gates read; main moved → rebase + re-verify (merge.md)
- [ ] 9  Endpoint: auto = merge.sh (runs from anywhere) · hold = PR-ready report, stop (full delegation in scope: merge.sh)
- [ ] 10 postmerge.sh <repo> <merge-sha> (every repo; a no-deploy repo then does its own step, deploy.md); exit 1 → impact decides: outage or many users = roll back, else fix forward (deploy.md)
- [ ] 11 Cleanup: pull the remote default branch, remove worktree, delete branches (+ screenshots ref), board rows; delegated lanes → lane-audit.sh;
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
- **11** Read `origin`’s remote default branch, then `git checkout <default> && git pull --ff-only` in the main checkout; inspect tracked changes, all untracked files and ignored files in the worktree; preserve needed assets and unrelated work, then use unforced `git worktree remove <path>` only when removal is safe; delete the branch
  locally and remotely, plus `refs/heads/screenshots/<issue>` on a screenshots PR. Prune other merged branches by SHA only
  (tip == a merged PR's `headRefOid`, or `ahead_by == 0`), never the remote default branch, an open-PR branch or a checked-out one. Board-owned
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
