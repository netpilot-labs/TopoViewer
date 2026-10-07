#!/usr/bin/env bash
# merge.sh <repo> <owner> <pr> [<worktree-branch>] [--wait-codex] — the merge step of SKILL.md
# step 5, executed: (worktree removed) → at-merge base check → pr-gates → squash-merge →
# postmerge.sh watch. Exit 0 only when the watch printed RESULT: clean.
#   base check: the PR head must CONTAIN origin/main (rebuilt/rebased PR). A Renovate branch
#   never does; it passes only when every file is under .github/workflows/ (no lockfile to go
#   inconsistent) and GitHub reports MERGEABLE/CLEAN (waits ≤12 min for Renovate's rebase).
#   --wait-codex: run pr-gates --watch first (Renovate PRs get "@codex review" from the pass).
#   merge slot: taken before the base check and held through the watch — the same per-repo slot dev-workflow's
#   merge.sh takes (dev-workflow/scripts/merge-slot.sh carries the rules; MERGE_SLOT_ACK after a non-clean watch).
#   containerlab-mcp: no deploy on merge — the PR run was the proof; no postmerge.
# Provenance: three merges hand-chained on 2026-09-09 12:40Z; the chain edited mid-run killed
# an instance (lazy read) — hence main().
set -uo pipefail
main() {
  REPO=$1; OWNER=$2; PR=$3; WT=${4:-}; WAITC=${5:-}
  SK=/Users/linzhu/git_projects/NetPilot-Claude/.claude/skills
  if [ "$WAITC" = "--wait-codex" ]; then "$SK/dev-workflow/scripts/pr-gates.sh" "$PR" --repo "$OWNER/$REPO" --watch 2>&1 | grep -E '^(READY|NOT READY|BROKEN|HEAD MOVED)' | tail -1; fi
  ROOT=/Users/linzhu/git_projects/NetPilot-Claude
  cd "$ROOT/$REPO" || return 1
  if [ -n "$WT" ] && [ -d "$ROOT/worktrees/$REPO/$WT" ]; then
    git worktree remove --force "$ROOT/worktrees/$REPO/$WT" && git branch -D "$WT" >/dev/null 2>&1; echo "worktree $WT removed"
  fi
  SLOT="$SK/dev-workflow/scripts/merge-slot.sh"; TOKEN=""; KEEP=0
  trap '[ -n "$TOKEN" ] && [ $KEEP = 0 ] && "$SLOT" release "$OWNER/$REPO" "$TOKEN"' EXIT; trap 'exit 130' INT TERM
  SLOT_OUT=$("$SLOT" acquire "$OWNER/$REPO" "$PR") || { echo "NOT merging: $SLOT_OUT"; return 1; }; TOKEN=$SLOT_OUT
  git fetch -q origin
  HEAD=$(gh pr view "$PR" --repo "$OWNER/$REPO" --json headRefOid --jq .headRefOid)
  MAIN=$(git rev-parse origin/main)
  if git merge-base --is-ancestor "$MAIN" "$HEAD"; then echo "base check: head ${HEAD:0:7} contains main ${MAIN:0:7}"
  else
    # Renovate branches never contain main. Allowed ONLY when every file is a workflow file (no
    # lockfile to go inconsistent) and GitHub reports the merge clean; wait up to 12 min for a
    # Renovate rebase + CI when it is not.
    FILES=$(gh pr view "$PR" --repo "$OWNER/$REPO" --json files --jq '[.files[].path]|join(" ")')
    for f in $(echo "$FILES"); do case "$f" in .github/workflows/*) ;; *) echo "BASE STALE and $f is not a workflow file — NOT merging $OWNER/$REPO#$PR"; return 1;; esac; done
    for i in $(seq 1 24); do
      MS=$(gh pr view "$PR" --repo "$OWNER/$REPO" --json mergeable,mergeStateStatus --jq '"\(.mergeable)/\(.mergeStateStatus)"')
      [ "$MS" = "MERGEABLE/CLEAN" ] && break; sleep 30
    done
    [ "$MS" = "MERGEABLE/CLEAN" ] || { echo "workflow-only PR not MERGEABLE/CLEAN after 12 min ($MS) — NOT merging"; return 1; }
    HEAD=$(gh pr view "$PR" --repo "$OWNER/$REPO" --json headRefOid --jq .headRefOid)
    echo "base check: workflow-only Renovate PR, behind main but $MS on head ${HEAD:0:7} (files: $FILES)"
  fi
  GATE=$("$SK/dev-workflow/scripts/pr-gates.sh" "$PR" --repo "$OWNER/$REPO" 2>&1 | grep -E '^(READY|NOT READY|BROKEN)')
  echo "gate: $GATE"; case "$GATE" in READY*) ;; *) echo "NOT merging"; return 1;; esac
  "$SLOT" check "$OWNER/$REPO" "$TOKEN" || { TOKEN=""; echo "merge slot was taken over (run paused past the stale limit?) — NOT merging"; return 1; }
  KEEP=1   # every repo: held from BEFORE the merge call; given back only on a proven outcome
  MOUT=$(gh pr merge "$PR" --repo "$OWNER/$REPO" --squash --delete-branch 2>&1); MRC=$?; echo "$MOUT" | tail -1
  if [ $MRC -ne 0 ]; then   # a pipe's status is tail's (shell.md) — this never gated before board 30
    case "$(gh pr view "$PR" --repo "$OWNER/$REPO" --json state --jq .state 2>/dev/null)" in OPEN|CLOSED) KEEP=0;; esac
    echo "MERGE FAILED rc=$MRC$([ $KEEP = 1 ] && echo ' — PR state not proven unmerged: the merge slot stays held, read the PR by hand')"; return 1
  fi
  SHA=""; for i in 1 2 3 4 5 6; do SHA=$(gh pr view "$PR" --repo "$OWNER/$REPO" --json mergeCommit --jq '.mergeCommit.oid // empty'); [ -n "$SHA" ] && break; sleep 5; done
  [ -n "$SHA" ] || { echo "no merge sha readable"; return 1; }
  echo "merged: $OWNER/$REPO#$PR -> $SHA at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  case "$REPO" in containerlab-mcp) KEEP=0;; *) "$SLOT" sha "$OWNER/$REPO" "$TOKEN" "$SHA";; esac   # no watch: released at exit · else postmerge.sh settles it
  git pull -q --ff-only origin main 2>/dev/null && echo "local main fast-forwarded"
  case "$REPO" in containerlab-mcp) echo "postmerge: none on merge for containerlab-mcp (ships with the next tagged release); the PR run was the proof"; return 0;; esac
  "$SK/dev-workflow/scripts/postmerge.sh" "$REPO" "$SHA"
}
main "$@"
