# Lanes — delegating to subagents (waiting IS a phase)

Applies to every delegated lane, full-implementation agents included. **Every brief starts from `lane-brief.md`** (the
template: where things are, authority + endpoint, owner rules, shared resources with wrappers, the deletion rule, lessons, the
report format); `scripts/lane-audit.sh` checks the lanes' leftovers afterwards (Lin, 2026-10-04).

- **Waiting is an action.** Before idling on a lane, arm a bounded background timer (`sleep 1200` + a one-line lane probe,
  `run_in_background`) whose completion re-invokes you; re-arm each time you go back to waiting; kill it when the lane closes.
  Completion notifications can be missed and a stalled lane emits none (55 min lost, 2026-08-13).
- **Brief rules:** issue-prefixed scratch filenames (`be712-pr-body.md` — two lanes clobbered one `pr-body.md` and pushed the
  wrong PR body, 2026-09-07); glob the scratchpad UUID, never retype it; the re-request step is the LAST line of a fix brief
  (agents drop trailing steps first); judges and graders run in the lane's FOREGROUND (`run_in_background: false`, BE#711);
  a lane that owns only SOME steps of an issue gets its own sub-issue to close — `Closes` on the shared one would
  close it under the sibling steps (clab#262).
- **The brief names every shared resource with its wrapper** (nine lanes at once, board 31, 2026-10-02): the local Postgres
  → `<skill-dir>/scripts/with-db-lock.sh <issue-id> …` (absolute path) around every backend suite and probe run, ONE hold per step, launched in the
  background with the longest timeout (its header has the why); a shared bench → the lane's lab-name prefix and the
  bench rules (`add-vendor/references/probe-loop.md` Bench ops); probes → the budget line on the issue before the first
  run (`probe-testing`); merges → they queue per repo, so expect `NOT MERGED`, wait, re-run from `--dry-run`.
- **Every brief states the deletion rule in its own text** (verbatim in `lane-brief.md`) — a subagent does not inherit
  caution it was not given: a lane ran `rm -rf ~/.claude/projects/"$d"` with `$d` empty and the machine's auto-memory and
  every session transcript were gone (2026-10-01).
- **Parallel lanes record lesson candidates on ONE fold-back issue** (a comment each, with its PR and date) and the wave's
  LAST issue lands them as one skills PR: the rules are written from the final fixes, and sibling lanes do not open colliding
  PRs on the same skill files. The issue is a board item, so this "later" has an owner; a lesson a sibling needs NOW still
  ships at once (board 31 feedback lane: skills#48 last, #49 and #50 mid-wave, 2026-10-01).
- **A lane can die silently mid-tool-call** (an HTTP 429 on the account spend limit kills every lane at once, board 24). Detect
  from the transcript: `tasks/<id>.output` last `timestamp` older than ~15 min with no tool_result = dead. Verify the worktree
  yourself and launch a FRESH lane from it; leave the old lane a SendMessage saying the work was taken over (it may wake hours
  later and find its worktree gone).
- **"Armed and waiting" is a claim to verify** (13 h lost, FE#203): after a lane reports pushing, confirm a `@codex review`
  newer than the head commit within minutes; any wait longer than one round (~20 min) = check the PR state AND the worktree's
  `git status` — finished work is often left uncommitted and is faster to finish in-hand than to re-brief.
- **Watch the WORKTREE, not liveness.** Signals by how early they fire: uncommitted-and-idle (dirty tree, no file touched
  ~12 min — the only one where work can be LOST) → unpushed (local HEAD ≠ PR head) → awaiting-us (unresolved threads whose last
  comment is Codex's AND older than ~15 min; younger fires on every round). Use git-tracked source mtimes, not the whole tree
  (clab#45, FE#216).
- **Nudge before you take over:** a precise SendMessage naming the remaining steps restarts a stalled lane in one round; take
  over only when unanswered, after a same-minute re-check.
- **ONE actor commits per worktree.** Stop the agent before committing its tree — a committer captures whatever is on disk,
  including a mutation proof mid-flight (FE#216).
- A repo-specific "clean pass = 👍" note narrows what you EXPECT, never what you CHECK — `pr-gates.sh` on every repo.
- A stall detector is a watcher: dry-run it once on a busy lane (must stay silent) and once with the threshold forced to 0
  (must fire); `git ls-files` paths are repo-relative — stat them from `(cd "$W" && …)`.
