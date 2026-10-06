# Merge — ready flip, CI gate, base check, the merge

Contents: the flip · CI never ran · base check · merging · migrations at merge · stacked PRs

## The flip (draft → ready)
Draft pushes skip every CI job on the four main repos, so the loop runs CI-free. Once Codex is dispositioned:
1. Main moved while the PR was a draft? Rebase FIRST: the flip's one CI run is then newer than main's tip and step 8's base
   check passes with no second CI + Codex round (BE PR#956). `t=$(date -u +%FT%TZ)` — taken BEFORE the action, never from
   memory (2026-09-09) — then `gh pr ready <n>`.
2. The flip mints a fresh Codex round only sometimes; force it with an explicit `@codex review` after the flip (4/4 PRs silent,
   2026-08-22). The gate holds until that request is answered (Lin, 2026-08-22). 👀 with no answer after ~15 min on a head that
   already carries a draft-phase verdict: post ONE more `@codex review`; unanswered for another ~15 min → report to Lin
   with the head verdict and stop — never merge on the older verdict, never wait silently for an hour (Lin, 2026-09-28,
   netpilot-skills#22; FE PR#515 waited 49 min).
3. `pr-gates.sh <n> --repo o/n --watch --wait-ci --since "$t"` waits for the post-flip verdict, then chains into
   `ci-wait.sh --since "$t"`, which finds the fresh `pull_request` run(s), waits, prints jobs, re-runs `pr-gates.sh` (run
   `ci-wait.sh` alone when the verdict is already in). `--since` is what keeps an OLDER run on the same head from reading green.
   Read ONLY its `ci-wait: FINAL …` line — a task log can carry an earlier watcher's READY (BE#743 merged on one). Disposition
   anything the flip round raised BEFORE merging (three PRs merged past post-flip findings, 2026-08-18).
4. A post-ready fix push re-runs CI — stamp `t` BEFORE that push too, the run is minted at the push (a `t` taken after the
   reply/resolve step made `ci-wait --since` wait for a run 7 s older than it, BE PR#929); for another full Codex round flip
   back with `gh pr ready --undo`. After ANY push, wait for
   that head's run to appear before `gh pr ready` — a flip seconds after a push gets its run cancelled by the concurrency group
   (BE PR#764).
The canonical `scripts/ci-jobs.py` checks required job names for known PR workflows; unknown workflows require every job to succeed. Keep its table aligned when those CI job names change. Backend real-Clerk auth is main-only and checked by `postmerge.sh`, not its PR gate.

CI green is defined once, in SKILL.md (the two gates). Read it at job level (`gh api "repos/o/r/actions/runs?head_sha=<full
oid>"`): `gh pr checks` lags a push and lies on a DIRTY PR.
**A repo with NO CI workflows** (`gh api repos/<o>/<r>/actions/workflows --jq .total_count` = 0; netpilot-skills today): the CI
half is the repo's own local check, run on the final tree and ATTESTED in the PR body as a line `local-check: <head7>
<what ran>` — `pr-gates.sh` grants CI N/A only when that line names the CURRENT head as the 7-char short SHA
(a full 40-char SHA fails its match, skills#28 2026-09-28; a new push needs a new line) — `for f in $(git ls-files '*.sh'); do
bash -n "$f" || exit 1; done` and `python3 -c 'import ast,sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]' $(git ls-files
'*.py')` (plus `scripts/lessons-lint.sh <clone>/dev-workflow` when that skill changed). Skip `ci-wait.sh` there (it waits 10 min for a run that cannot
exist and exits 3); after the flip + explicit request run `pr-gates.sh` directly: with the attestation in place it prints `CI: N/A` and READY.
containerlab-mcp has CI (Tests + Cloud Release Package) but no deploy on merge: the PR run is the proof and the release is
tag-gated — merging is not shipping (clab#45).

## CI never ran (zero runs on the head)
0. **`githubstatus.com` first** (`curl https://www.githubstatus.com/api/v2/incidents/unresolved.json`) — an Actions outage
   mimics every step below on every head. Hold the merge, poll ~30 min, then `gh pr ready --undo && sleep 30 && gh pr ready`
   mints a fresh run on the same head (FE PR#334, BE#428).
1. `gh pr view --json mergeable,mergeStateStatus`: `CONFLICTING`/`DIRTY` gets NO runs until the conflict is resolved (a
   `merge origin/<default>` commit is fine) — a sibling merge flips a long-open PR silently (FE PR#199, clab PR#140, BE PR#723).
2. `gh pr close <n> && gh pr reopen <n>` re-fires on the SAME head (the Codex verdict survives); also the fix when a flip
   minted only the draft-era skipped run (BE PR#688).
3. Still zero after ~3 min → new head (empty commit / rebase) — invalidates the verdict, re-request.
A run that EXISTS but stays `queued` through an outage is dead even after runners recover (`gh run rerun` refuses a queued
run; `ci-wait.sh` would wait its full 25 min on it) — once sibling runs execute again, close/reopen mints a fresh run on the
same head (BE PR#428).
A ~3 s red annotated "payments have failed / spending limit" is an account billing block — Lin only. A 4 s job failure with
zero failed steps is infrastructure — `gh run rerun --failed`. CI red while local parity is green → check whether main advanced
(PR CI builds the MERGE commit; FE PR#194). Ruff unpinned in a workflow turns `main` red on a ruff release — reproduce on `main`
first (clab#40).

## Base check — `merge.sh o/n <pr> --dry-run`, its OWN command, output READ before any merge call
The script reads the base, the carve-out and the merge ref from the API (its header carries each why); chaining check and
merge by hand in one line merged stale bases three times (FE PR#247, #276, BE PR#528). What its `FINAL` lines ask of you:
- **"rebase and re-verify"** — main moved and the carve-out (Lin, 2026-08-07: every required run green AND created after
  main's tip, with successful jobs' immutable checkout commit parents proving the current default tip and exact PR head)
  does not hold: rebase, then CI + Codex again, even with no file overlap (CI builds the merge commit; `CLEAN
  MERGEABLE` never meant up to date). Lockfile PR: rebuild on current main, `pnpm install --frozen-lockfile` on that tree.
- **"stale merge ref"** — GitHub has not recomputed `refs/pull/<n>/merge` since a sibling merge: close/reopen, then re-verify
  (FE#489, BE PR#803). `mergeable=UNKNOWN` is that recompute still running — re-run in a moment (BE PR#935).
- **"merge slot … held"** — one merge per repo at a time on this machine (`merge-slot.sh`; skills PR#55). Held by a PR whose
  watch is running: wait for its `postmerge.sh`, then start again at `--dry-run` — main moved. Held by a watch that ended
  RED / BROKEN / REVIEW: read that result first (deploy.md); its fix or revert — or the next merge once every line is
  attributed — runs as `MERGE_SLOT_ACK=<that pr> merge.sh …`. Never delete a slot by hand. The slot is machine-local: with
  agents merging in one repo from two machines, sequence those merges yourself (each waits for the other's watch).
- **Any PR carrying a migration:** `uv run alembic heads` on the rebased branch prints ONE head, and Neon's `alembic current`
  equals the new `down_revision`; else re-point it (BE PR#716 + #719 forked the chain).

The carve-out reads the selected run attempt's successful job logs and standard `actions/checkout` merge SHA,
then verifies its two Git parents. Missing/expired logs, custom checkout names or multiple checkouts require rebase;
review the proof reader before adopting a changed checkout log format. A timestamp alone never proves the tested base.

## Merging — `merge.sh o/n <pr>`
- **The script is the only merge command:** it merges from outside any checkout with the full head oid and asserts `MERGED`
  (FE#106, BE#287, BE PR#560, BE#464) — the deploy watch starts from its `FINAL MERGED <oid>` line, nothing earlier. A remote
  branch that survived a merge: `gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>`, never a second merge attempt.
  `gh api … --jq .head.sha` lags a push 5–40 s — retry before calling it a head move (BE PR#803; BE PR#915).
- **Vercel gates production deploys on the squash commit's AUTHOR** (inherited from the branch commits): every
  Frontend/Marketing branch commit is authored `lz-networks <50209324+lz-networks@users.noreply.github.com>`; a blocked
  deployment cannot be redeployed — only a fresh lz-networks-authored commit to main unblocks (FE PR#233).
- `Closes #NN` closes with a ~1-min lag; verify before reporting. **Use the BARE GitHub number
  (`Closes #944` / `Fixes #944`, or `owner/repo#944` cross-repo) — our `BE#`/`FE#` shorthand is NOT a
  valid closing keyword** (`Fixes BE#944` links/closes nothing): the issue stays OPEN after merge. Verify
  each linked issue actually closed and close by hand if the auto-close missed (BE#944/#945, 2026-10-01).

## Migrations at merge — the agent's own in default mode since 2026-10-04 (authority.md Delegation modes)
Additive/data migrations: apply to Neon BEFORE merge (new code needs the schema). DROP migrations on tables the deployed code
still touches: merge → deploy → verify → run the docstring's pre-apply check → apply (BE PR#570).

## Stacked PRs
Retarget the child to the repository’s default branch BEFORE squash-merging its base (`gh pr edit <child> --base <default-branch>`), then rebase the child
`--onto origin/<default-branch> <old-base-tip>` — merging the base with `--delete-branch` auto-closes the child unrecoverably
(clab PR#193→#195).
