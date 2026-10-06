#!/bin/bash
# required-workflows.sh <owner/repo> <pr>
# Prints one "<path>\t<name>" line per workflow that must have a run on the PR's CURRENT head. The ONE
# definition of the required set for pr-gates.sh, ci-wait.sh and merge.sh (three copies had drifted).
#   required = every non-Vercel workflow that ran (event=pull_request) on this PR's branch SINCE THIS PR
#              WAS CREATED and is still active, plus matching active PR declarations before their first run.
# WHY both bounds: Renovate reuses branch names, so a branch's run history holds EARLIER PRs' runs — a
# workflow since removed from the repo (FE#587, FE#588) or path-filtered and triggered only by an earlier
# PR's diff (clab#270, On-Prem Bundle) was demanded on a head it can never run on; three hand-merges, one
# a critical CVE (Lin, 2026-10-05). An event miss on THIS PR is still caught: its earlier runs stay in the set.
# Exit: 0 = set printed (may be empty)   2 = a read failed, set unknown — callers fail CLOSED.
set -uo pipefail
REPO="${1:-}"; PR="${2:-}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && [[ "$PR" =~ ^[0-9]+$ ]] || { echo "usage: required-workflows.sh <owner/repo> <pr>" >&2; exit 2; }
meta="$(gh pr view "$PR" -R "$REPO" --json createdAt,headRefName,headRepository,headRepositoryOwner \
        --jq '"\(.createdAt)\t\(.headRefName)\t\(.headRepositoryOwner.login // "")/\(.headRepository.name // "")"' 2>/dev/null)" || exit 2
IFS=$'\t' read -r created headref headrepo <<< "$meta"
[[ "$created" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && [ -n "$headref" ] || exit 2
[[ "$headrepo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || exit 2   # head repo gone (deleted fork): set unknown
# Joined on workflow ID, never on the run's path: the runs API may suffix it (`.github/workflows/x.yml@main`) and an
# exact path match would then drop every run and print an empty set with exit 0 (Codex, PR#72 post-flip). The path
# printed is the workflows API's own, unsuffixed — pr-gates.sh compares it with the PR's file list.
active="$(gh api "repos/$REPO/actions/workflows" --paginate --jq '.workflows[]|select(.state=="active")|"\(.id)\t\(.path)\t\(.name)"' 2>/dev/null)" || exit 2
# >= keeps a run minted in the same second the PR opened; both stamps are GitHub's second-precision UTC.
# The head-repository match keeps a fork PR that shares the branch name out of the set (Codex, PR#72).
hist="$(gh api "repos/$REPO/actions/runs" -X GET -f "branch=$headref" -f event=pull_request -f per_page=100 --paginate \
        --jq "[.workflow_runs[]|select(.name!=\"Vercel\")|select(.created_at >= \"$created\")|select((.head_repository.full_name // \"\") == \"$headrepo\")] as \$runs | if any(\$runs[]; ((.pull_requests // []) | length) == 0) then error(\"PR association missing\") else [\$runs[]|select(any(.pull_requests[]?; .number == $PR))|.workflow_id]|unique|.[] end" 2>/dev/null)" || exit 2
hist="$(printf '%s\n' "$hist" | sort -u)"   # --jq deduplicates each page; collapse duplicate workflow IDs across pages, regardless of historical display names.
# A workflow may be required before its first associated run exists. Inspect only unseen
# active declarations; complex/filtered unknowns fail closed rather than declare CI green.
proofdir=$(mktemp -d) || exit 2
trap 'rm -rf "$proofdir"' EXIT
printf '%s\n' "$active" > "$proofdir/active"
printf '%s\n' "$hist" > "$proofdir/history"
extra=$(python3 "$(dirname "$0")/unseen-pr-workflows.py" "$REPO" "$PR" "$proofdir/active" "$proofdir/history") || exit 2
while IFS= read -r id; do
  [[ "$id" =~ ^[0-9]+$ ]] || { [ -z "$id" ] && continue; exit 2; }   # a run with no numeric workflow id: set unknown
  line="$(printf '%s\n' "$active" | awk -F'\t' -v id="$id" '$1==id{print $2 "\t" $3; exit}')"
  [ -n "$line" ] && printf '%s\n' "$line"
done <<< "$hist"
[ -z "$extra" ] || printf '%s\n' "$extra"
exit 0
