#!/usr/bin/env bash
# ci-wait.sh <pr> --repo owner/name [--since <ISO-UTC>] [--timeout-min N]
#
# Waits for the PR head's `pull_request` CI run to conclude, prints its jobs, then runs
# pr-gates.sh on the PR. Use it after `gh pr ready`, after a close/reopen re-verify, or
# after any push — the three moments a hand-rolled "find the run, watch it, re-gate"
# chain has been written wrong (2026-09-09: `gh api --jq --arg` swallowed the flag and
# the waiter polled for a run it could never match).
#   --since   only accept a run created at or after this instant (inclusive — a flip in the same
#             second as the timestamp is common; PR #23 R2) (default: the newest run on
#             the head); pass the timestamp taken just before the flip/reopen so an OLD
#             skipped/draft-era run is never mistaken for the fresh one.
# Exit: pr-gates.sh's exit (0 READY / 1 NOT READY / 2 BROKEN); 3 = no run minted in time.
# Result line: "ci-wait: FINAL READY|NOT READY|BROKEN …" on EVERY exit — read THAT, never an earlier READY.
# (merge.md "CI never ran": githubstatus first, mergeStateStatus, then close/reopen, then a new head).
# Constants: TIMEOUT_MIN=25 covers the longest fleet suite (frontend coverage ~12 min);
# a run that has not even appeared after APPEAR_MIN=10 is the never-triggers signature; DISCOVER_S=120
# bounds the wait for a repo's OTHER workflows to become visible (both observed multi-workflow repos
# minted theirs within a minute of each other; clab#197).
# The whole body runs inside main() so an edit to this file while an instance is running
# cannot change that instance mid-flight (bash reads scripts lazily; 2026-09-09: an edit
# killed a live ci-wait with a syntax error at the line being rewritten).
main() {
set -uo pipefail
pr=${1:?pr number}; shift
repo=""; since=""; TIMEOUT_MIN=25; APPEAR_MIN=10; DISCOVER_S=120
while [ $# -gt 0 ]; do case "$1" in
  --repo) repo=$2; shift 2;; --since) since=$2; shift 2;; --timeout-min) TIMEOUT_MIN=$2; shift 2;;
  *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ -n "$repo" ] || { echo "--repo owner/name required" >&2; exit 2; }
head=$(gh pr view "$pr" -R "$repo" --json headRefOid -q .headRefOid)
echo "ci-wait: $repo#$pr head=$head since=${since:-newest}"
# A repo can run SEVERAL workflows on one pull_request event (containerlab-mcp: Tests +
# Cloud Release Package) — wait for every non-skipped run on the head, not the first one
# found (2026-09-09, clab#197: the first run finished while Tests was still in progress).
appear=$(( $(date +%s) + APPEAR_MIN*60 )); ids=""
while [ -z "$ids" ]; do
  ids=$(gh api "repos/$repo/actions/runs?head_sha=$head&event=pull_request&per_page=30" \
       --jq ".workflow_runs | map(select(.created_at >= \"${since}\")) | map(select(.conclusion != \"skipped\")) | map(.id) | unique | .[]" | tr '\n' ' ')
  [ -n "$ids" ] && break
  [ $(date +%s) -gt $appear ] && { echo "ci-wait: no run minted in ${APPEAR_MIN} min — check mergeStateStatus, then close/reopen (merge.md, CI never ran)"; echo "ci-wait: FINAL BROKEN rc=3 (no run minted)"; exit 3; }
  sleep 15
done
# Workflows become API-visible at different times (PR #23 R5): keep discovering until two consecutive
# reads agree or every required workflow (required-workflows.sh) has a run, bounded by DISCOVER_S.
SK="$(cd "$(dirname "$0")" && pwd)"
read_expected() { local req; req=$("$SK/required-workflows.sh" "$repo" "$pr") || return 2; printf '%s\n' "$req" | cut -f2 | sort -u; }
dstart=$(date +%s); prev=""
while :; do
  # the required set is re-read every pass (a workflow added by this PR appears late) and fails CLOSED (#27 R4)
  expected_names=$(read_expected) || { echo "ci-wait: cannot read the branch's run history — required set unknown"; echo "ci-wait: FINAL BROKEN rc=3 (history unreadable)"; exit 3; }
  # ONE read gives both the ids and the distinct workflow names, so a break never leaves stale ids behind
  lines=$(gh api "repos/$repo/actions/runs?head_sha=$head&event=pull_request&per_page=30" \
          --jq ".workflow_runs[]|select(.created_at >= \"${since}\")|select(.conclusion != \"skipped\")|\"\\(.id) \\(.name)\"" 2>/dev/null)
  cur=$(printf '%s\n' "$lines" | awk 'NF{print $1}' | sort -u | tr '\n' ' ')
  have_names=$(printf '%s\n' "$lines" | awk 'NF{$1=""; sub(/^ /,""); print}' | sort -u)
  [ -n "$cur" ] && ids="$cur"
  # settle only on two CONSECUTIVE agreeing reads whose NAMES cover every expected workflow (#27 R2, R3)
  missing=$(comm -23 <(printf '%s\n' "$expected_names" | grep -v '^$') <(printf '%s\n' "$have_names" | grep -v '^$'))
  if [ -n "$cur" ] && [ "$cur" = "$prev" ] && [ -z "$missing" ]; then break; fi
  prev="$cur"
  if [ $(( $(date +%s) - dstart )) -ge $DISCOVER_S ]; then echo "ci-wait: discovery bound reached; still no run for:$(printf '%s\n' "$missing" | sed 's/^/ [/; s/$/]/' | tr -d '\n') — waiting on the visible ones"; break; fi
  sleep 15
done
echo "ci-wait: runs on head: $ids"
deadline=$(( $(date +%s) + TIMEOUT_MIN*60 ))
for id in $ids; do
  echo "ci-wait: run $id ($(gh api "repos/$repo/actions/runs/$id" --jq '.name + " created " + .created_at'))"
  while :; do
    st=$(gh api "repos/$repo/actions/runs/$id" --jq '.status + "/" + (.conclusion // "")')
    case "$st" in completed/*) break;; esac
    [ $(date +%s) -gt $deadline ] && { echo "ci-wait: run $id still $st after ${TIMEOUT_MIN} min"; echo "ci-wait: FINAL BROKEN rc=3 (run did not conclude)"; exit 3; }
    sleep 30
  done
  echo "ci-wait: run $id concluded ${st#completed/}"
  gh api "repos/$repo/actions/runs/$id/jobs" --jq '.jobs[]|"  job \(.name): \(.conclusion)"'
done
"$(dirname "$0")/pr-gates.sh" "$pr" --repo "$repo"; rc=$?
# The ONLY line a caller may read for the result. A task log can carry an earlier stage's
# "READY" (a pr-gates --watch that ran before the flip): grepping READY merged BE#743 with
# its unit-test job still running (2026-09-09). Read this marker, nothing else.
case $rc in 0) echo "ci-wait: FINAL READY";; 1) echo "ci-wait: FINAL NOT READY";; *) echo "ci-wait: FINAL BROKEN rc=$rc";; esac
exit $rc
}
main "$@"
