# Lane brief — the template a coordinator fills in for EVERY delegated lane

Copy it whole, fill every `<…>`, delete nothing: a lane knows only what its brief says (`lanes.md` has the why behind each
section; the deletion rule below is quoted verbatim because a subagent does not inherit caution it was not given).
Lin, 2026-10-04 — distilled from the brief board 31's 14 lanes ran on (2026-10-01/02).

```
# Lane <id> — <issue or task title> (read fully before starting)
You are one of <n> lanes running IN PARALLEL on <board / task>. A coordinator session spawned you and reads only your
final message. Stay inside <issue>; anything that belongs elsewhere: one comment on the owning issue + a line in your report.

## Where things are
- Workspace root: /Users/linzhu/git_projects/NetPilot-Claude (NOT a git repo; each subfolder is one). Your repos:
  <repo (owner/repo)> …; all on main, clean, fast-forwarded <date>.
- Root skills: /Users/linzhu/git_projects/NetPilot-Claude/.claude/skills/ — load with the Skill tool. `dev-workflow` is
  mandatory: its flow, its scripts by ABSOLUTE path (worktree under NetPilot-Claude/worktrees/<repo>/<branch>, draft PR,
  `@codex review` loop, ready flip, merge.sh, postmerge.sh, cleanup, learning pass). Read each phase file at its phase.
- Scratch dir (SHARED by every lane — prefix every file with your issue id, e.g. `be947-pr-body.md`, and read line 1 back
  before `gh pr edit --body-file`): <scratchpad path>

## Authority and endpoint
- Delegation mode (dev-workflow authority.md "Delegation modes"): <default | full — "Delegation: full, Lin <date>, scope: <task/project>">.
  Under full: the endpoint is merge-and-finish — gates green (CI on the current head + Codex dispositioned) → merge.sh →
  postmerge.sh → cleanup → learning-pass comment; the PR body carries the delegation line. Under default: agent/auto merges;
  agent/hold, and any diff on the never-auto list, stops at PR-ready (the two guardrail carve-outs in SKILL.md still apply;
  a one-off merge say-so from Lin for THIS lane, quoted here, is the other exception: <none | quote>).
- If the permission system DENIES a merge or any other call: do not retry or work around it; leave the PR READY with both
  gates green and say so in your report.
- The PR body carries a real `Closes <owner>/<repo>#<n>` for your issue (an issue-less task: the authority line instead, as a
  session-owned PR). Board readme rows: <the coordinator rewrites them from your report | you rewrite YOUR rows per
  project-management's status discipline>; never other lanes' rows or board items.

## Owner rules that apply
- <the rules in force for this work — e.g. agent-facing text is concise and fixed in place, never duplicated; nothing enters a
  guide as a fact until observed (bench or probe), observation quoted on the issue; evidence lives on the issue, never in a
  run folder or local file>

## Shared resources — each with its wrapper
- Local Postgres `netpilot-db`, ONE consumer at a time: wrap every backend `pytest` and probe-lab run in
  <skill-dir>/scripts/with-db-lock.sh <your-issue-id> <command…> (waits, runs, releases).
- Bench VM <name | none> (<project, zone, size, package>): reach it with `gcloud compute ssh <name> --zone <z> --project
  netpilot-ai --tunnel-through-iap --command '…'`; your lab prefix `<prefix>-`, your mgmt network `<name>` / `<subnet>`;
  destroy ONLY labs you deployed; never stop, reconfigure or re-package the VM; destroy your labs when done.
- Merges queue per repo: merge.sh answers NOT MERGED while a sibling's merge + deploy watch is in flight — wait, re-run from
  --dry-run (its base check may then ask for a rebase + re-verify). Sibling PRs in the same repo are expected.
- Probes (`probe-testing`): cheapest tier that settles the question, default n=1, the budget line on the issue BEFORE the
  first run, hard cap $<n> per lane; judges run in YOUR foreground; long probes launch from the MAIN checkout with
  NETPILOT_BACKEND_DIR=<your worktree>.

## Deletion rule (verbatim — it applies to you)
Nothing under `~/.claude/` is ever deleted (a leftover dir is named in the report). No `rm -rf` runs on a variable- or
glob-built path until the expanded path has been printed and seen non-empty and inside your own worktree, run folder or
scratch prefix.

## Lessons
<Record lesson candidates (a rule, gotcha or script idea worth keeping) as ONE comment on <fold-back issue> with your PR link
and the date | in your final message>; then your PR's last comment is `learning-pass: none (candidates on <issue>)` or
`learning-pass: none (<why nothing>)`.

## Your final message (the coordinator reads only this; keep it under 25 lines)
PR link · merge SHA (or "READY, not merged: <why>") · deploy/postmerge verdict · the evidence in 3–6 lines (numbers, decisive
quotes) · anything in the issue you did NOT do and why · lesson candidates · any leftover (worktree, lab, run dir).
```

After the lanes report: `<skill-dir>/scripts/lane-audit.sh <owner/repo> <issue>… [pr:<n>…]` (absolute path, as every script here) checks each one's issue, PR (an issue-less lane
by `pr:<n>`), worktree, remote branch and slot in one read; then `loose-ends.sh` ONCE for the whole wave (SKILL.md step 11).
