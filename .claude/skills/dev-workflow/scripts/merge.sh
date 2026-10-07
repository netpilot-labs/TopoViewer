#!/usr/bin/env bash
# merge.sh <owner/repo> <pr> [--dry-run] — the merge step of dev-workflow, executed.
#
# Runs from ANYWHERE: every check is a GitHub API read and the script cd's into a temp dir first, so
# `gh pr merge --delete-branch` never runs inside a checkout (the local cleanup fails there and the
# remote delete is silently skipped — FE#106, BE#287).
# Steps, each its own gated read (chaining check and merge in one line merged stale bases three
# times — FE PR#247, #276, BE PR#528):
#   1 PR must be OPEN and not a draft (flip + ci-wait first; merge.md).
#   1b Merge slot (real run): `merge-slot.sh acquire` — one merge per repo at a time on this machine, held
#     through the deploy watch (merge-slot.sh carries the why and the rules). A dry run only reports it.
#   2 Base check: compare main...head → behind_by == 0, else the carve-out: EVERY required
#     workflow's (all but Vercel) latest run is green and was created AFTER main's tip commit
#     (both UTC, from the API — a local-offset string compare merged a stale base, BE PR#842);
#     within CARVEOUT_MARGIN_S = stale; and the gate in step 4 then runs with --since <main tip>.
#     Stale → exit 1 "rebase and re-verify".
#   3 Merge-ref check: the test merge commit's first parent must be main's tip; GitHub does not
#     recompute refs/pull/N/merge on a base push until something touches the PR (BE PR#803).
#   4 pr-gates.sh must print READY (Codex dispositioned on the head + CI green + request answered).
#   5 Re-read the base tip + merge ref RIGHT before merging (--match-head-commit pins only our head).
#   6 Slot still ours (`merge-slot.sh check`), then gh pr merge --squash --delete-branch --match-head-commit <full oid>; poll for state=MERGED AND a
#     40-char merge oid; the merge commit's first parent must be the tip read in step 5.
# Result line: "merge.sh: FINAL MERGED <oid>" | "FINAL NOT MERGED <reason>" | "FINAL BROKEN".
# Read THAT line only. Exit 0 merged · 1 not merged (reason printed) · 2 broken (trust nothing).
# --dry-run runs steps 1–4 and stops (a missing merge ref fails the dry run too).
# Constants: CARVEOUT_MARGIN_S=60 — merge/squash commits stamp committer date at merge time and
# a run created within a minute of main's tip cannot have built against it (Lin, 2026-08-07).
main() {
set -uo pipefail
usage() { echo "usage: merge.sh <owner/repo> <pr> [--dry-run]" >&2; exit 2; }
[ $# -eq 2 ] || [ $# -eq 3 ] || usage
REPO=$1; PR=$2; DRY=0
case "${3:-}" in "") ;; --dry-run) DRY=1 ;; *) echo "merge.sh: unknown argument '$3' — refusing to guess on a merge command (PR #23 R3)" >&2; usage ;; esac
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage; [[ "$PR" =~ ^[0-9]+$ ]] || usage
CARVEOUT_MARGIN_S=60
final() { echo "merge.sh: FINAL $1${DRYDRAFT:-}"; exit "$2"; }   # DRYDRAFT carries the draft caveat on EVERY dry-run exit
SK="$(cd "$(dirname "$0")" && pwd)"          # resolved BEFORE leaving the caller's cwd
TMPD=$(mktemp -d) || final "BROKEN mktemp failed (TMPDIR full or unavailable)" 2
cd "$TMPD" || final "BROKEN cannot cd to $TMPD" 2                   # never run `gh pr merge --delete-branch` inside a checkout: the local
                                              # cleanup fails there and the remote delete is silently skipped (FE#106, BE#287)

# self-test the source first (deploy.md: a watcher whose reads all fail looks identical to a quiet one)
meta=$(gh pr view "$PR" -R "$REPO" --json state,isDraft,headRefOid,baseRefName,mergeable,mergeStateStatus,headRefName \
       --jq '"\(.state) \(.isDraft) \(.headRefOid) \(.baseRefName) \(.mergeable) \(.mergeStateStatus) \(.headRefName)"' 2>/dev/null) || final "BROKEN cannot read $REPO#$PR" 2
read -r STATE DRAFT HEAD BASE MERGEABLE MSS HEADREF <<< "$meta"
[ "${#HEAD}" = 40 ] || final "BROKEN head oid unreadable: '$HEAD'" 2
echo "merge.sh: $REPO#$PR state=$STATE draft=$DRAFT base=$BASE head=${HEAD:0:10} mergeable=$MERGEABLE/$MSS"
[ "$STATE" = "OPEN" ] || final "NOT MERGED state=$STATE" 1
DEFAULT_BASE=$(gh api "repos/$REPO" --jq .default_branch 2>/dev/null) || final "BROKEN cannot read repository default branch" 2
[ -n "$DEFAULT_BASE" ] || final "BROKEN repository default branch is empty" 2
[ "$BASE" = "$DEFAULT_BASE" ] || final "NOT MERGED base is $BASE, not default $DEFAULT_BASE — a stacked/mis-targeted PR is retargeted first (merge.md, Stacked PRs)" 1
[ "$DRAFT" = "false" ] || { [ $DRY = 1 ] && { echo "merge.sh: (dry-run) PR is still a DRAFT — flip + ci-wait before a real run"; DRYDRAFT=" (draft — a real run refuses until the flip)"; } || final "NOT MERGED still a draft — gh pr ready, then ci-wait.sh, then re-run" 1; }
# UNKNOWN is GitHub still recomputing mergeability after a base push, not a conflict (BE PR#935, 2026-10-01)
[ "$MERGEABLE" != "UNKNOWN" ] || final "NOT MERGED mergeable=UNKNOWN ($MSS) — GitHub is still recomputing after a base push, not a conflict; re-run in a moment" 1
[ "$MERGEABLE" = "MERGEABLE" ] || final "NOT MERGED mergeable=$MERGEABLE ($MSS) — resolve the conflict first" 1

# 1b merge slot
TOKEN=""; KEEP=0; MERGED=""
if [ $DRY = 1 ]; then "$SK/merge-slot.sh" peek "$REPO" | sed 's/^/merge.sh: (dry-run) /'
else
  trap '[ -n "$TOKEN" ] && [ $KEEP = 0 ] && "$SK/merge-slot.sh" release "$REPO" "$TOKEN" ${MERGED:+merged}' EXIT; trap 'exit 130' INT TERM
  SLOT_OUT=$("$SK/merge-slot.sh" acquire "$REPO" "$PR") || final "NOT MERGED $SLOT_OUT" 1
  TOKEN=$SLOT_OUT
fi

# 2 base check
MAIN_TIP=$(gh api "repos/$REPO/commits/$BASE" --jq .sha 2>/dev/null); MAIN_DATE=$(gh api "repos/$REPO/commits/$BASE" --jq .commit.committer.date 2>/dev/null)
[ "${#MAIN_TIP}" = 40 ] || final "BROKEN cannot read $BASE tip" 2
BEHIND=$(gh api "repos/$REPO/compare/$BASE...$HEAD" --jq .behind_by 2>/dev/null)
[[ "$BEHIND" =~ ^[0-9]+$ ]] || final "BROKEN compare returned '$BEHIND'" 2
[ -n "$MAIN_DATE" ] || final "BROKEN cannot read $BASE tip date" 2
GATE_SINCE=""
if [ "$BEHIND" = "0" ]; then
  echo "merge.sh: base check — head contains $BASE tip ${MAIN_TIP:0:10}"
else
  # Every REQUIRED workflow (all but Vercel) must have its LATEST run green and newer than main's
  # tip — one fresh run of one workflow never vouches for the others (PR #23 R3).
  runs_json=$(gh api "repos/$REPO/actions/runs?head_sha=$HEAD&event=pull_request&per_page=50" \
              --jq '[.workflow_runs[]|select(.name!="Vercel")]|group_by(.name)|map(sort_by(.created_at)|last)' 2>/dev/null)
  [ -n "$runs_json" ] || final "BROKEN cannot list runs on the head" 2
  total=$(printf '%s' "$runs_json" | python3 -c 'import json,sys; r=json.load(sys.stdin); print(len(r))')
  okc=$(printf '%s' "$runs_json" | python3 -c 'import json,sys; r=json.load(sys.stdin); print(sum(1 for x in r if x.get("conclusion")=="success"))')
  RUN_DATE=$(printf '%s' "$runs_json" | python3 -c 'import json,sys; r=json.load(sys.stdin); d=[x["created_at"] for x in r if x.get("conclusion")=="success"]; print(min(d) if d else "")')
  [ "${total:-0}" -gt 0 ] && [ "$okc" = "$total" ] && [ -n "$RUN_DATE" ] || final "NOT MERGED base is $BEHIND commit(s) behind $BASE and not every required workflow's latest run is green ($okc/$total) — rebase and re-verify" 1
  # The required SET is independent of this head's run list (required-workflows.sh): a required workflow
  # with no run on the current head is an event miss this head's run list cannot show (PR #23 R4).
  required=$("$SK/required-workflows.sh" "$REPO" "$PR") || final "BROKEN cannot read the required-workflow set — trust nothing" 2
  expected_json=$(printf '%s\n' "$required" | python3 -c 'import json,sys; print(json.dumps(sorted({l.rstrip("\n").split("\t",1)[1] for l in sys.stdin if "\t" in l})))')
  missing=$(printf '%s\n%s' "$runs_json" "$expected_json" | python3 -c 'import json,sys; a,b=sys.stdin.read().split("\n",1); have={x["name"] for x in json.loads(a)}; exp=json.loads(b) if b.strip() else []; print(", ".join(w for w in exp if w not in have))')
  [ -z "$missing" ] || final "NOT MERGED base is $BEHIND behind and required workflow(s) minted no run on this head: $missing — close/reopen (merge.md, CI never ran), then re-verify" 1
  to_epoch() { python3 -c "import sys,datetime;print(int(datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).timestamp()))" "$1" 2>/dev/null; }
  run_s=$(to_epoch "$RUN_DATE"); main_s=$(to_epoch "$MAIN_DATE")
  # an empty conversion is 0 to bash arithmetic and would PASS the carve-out (PR #23 R3): validate both
  [[ "$run_s" =~ ^[0-9]+$ ]] && [[ "$main_s" =~ ^[0-9]+$ ]] || final "BROKEN cannot parse run date '$RUN_DATE' or $BASE tip date '$MAIN_DATE' — trust nothing" 2
  if [ $(( run_s - main_s )) -gt $CARVEOUT_MARGIN_S ]; then
    echo "merge.sh: base check — $BEHIND behind, CARVE-OUT applies: oldest of the $total required workflows' latest green runs ($RUN_DATE) is newer than $BASE tip $MAIN_DATE (UTC compare)"
    GATE_SINCE="$MAIN_DATE"   # the gate below must also see only runs newer than main's tip
  else
    final "NOT MERGED base is $BEHIND behind and a required workflow's latest green run ($RUN_DATE) is not newer than $BASE tip ($MAIN_DATE) — rebase and re-verify CI + Codex" 1
  fi
fi

# 3 merge-ref first parent
MERGE_SHA=$(gh api "repos/$REPO/pulls/$PR" --jq '.merge_commit_sha // ""' 2>/dev/null)
if [ -n "$MERGE_SHA" ]; then
  P1=$(gh api "repos/$REPO/commits/$MERGE_SHA" --jq '.parents[0].sha' 2>/dev/null)
  if [ "$P1" = "$MAIN_TIP" ]; then echo "merge.sh: merge ref — first parent is $BASE tip"
  else final "NOT MERGED test-merge commit's first parent ${P1:0:10} != $BASE tip ${MAIN_TIP:0:10} (stale merge ref) — touch the PR (close/reopen) and re-verify" 1; fi
else
  final "NOT MERGED merge ref not computed yet — re-run in a minute" 1
fi

# 4 the two gates
if [ -n "$GATE_SINCE" ]; then "$SK/pr-gates.sh" "$PR" --repo "$REPO" --since "$GATE_SINCE" > /tmp/merge-gate.$$ 2>&1; rc=$?
else "$SK/pr-gates.sh" "$PR" --repo "$REPO" > /tmp/merge-gate.$$ 2>&1; rc=$?; fi
grep -E '^(READY|NOT READY|BROKEN)' /tmp/merge-gate.$$ | head -1; rm -f /tmp/merge-gate.$$
[ $rc -eq 0 ] || final "NOT MERGED pr-gates rc=$rc" $([ $rc -eq 2 ] && echo 2 || echo 1)
[ $DRY = 1 ] && final "DRY-RUN ok — steps 1–4 pass on head ${HEAD:0:10}" 0

# 5 re-read the base RIGHT before merging: the gate takes seconds and another session can merge
# to main meanwhile; --match-head-commit pins only OUR head, never the base (PR #23 R1 P1).
TIP2=$(gh api "repos/$REPO/commits/$BASE" --jq .sha 2>/dev/null); BEHIND2=$(gh api "repos/$REPO/compare/$BASE...$HEAD" --jq .behind_by 2>/dev/null)
P1B=$(gh api "repos/$REPO/pulls/$PR" --jq '.merge_commit_sha // ""' 2>/dev/null); [ -n "$P1B" ] && P1B=$(gh api "repos/$REPO/commits/$P1B" --jq '.parents[0].sha' 2>/dev/null)
if [ "$TIP2" != "$MAIN_TIP" ] || { [ "$BEHIND2" != "0" ] && [ "$BEHIND" = "0" ]; } || [ "$P1B" != "$TIP2" ]; then
  final "NOT MERGED $BASE moved during the gate (${MAIN_TIP:0:10} → ${TIP2:0:10}; merge ref parent ${P1B:0:10}) — re-run from the top" 1
fi

# 6 merge + assert; the merge oid can lag state=MERGED by a few seconds (PR #23 R1 P2)
# The slot must still be OURS (a run paused past the stale limit was taken over). EVERY repo keeps it from BEFORE the
# merge call — an interrupt mid-call can leave a merge GitHub already accepted — and gives it back only on a proven
# outcome: not merged, or merged in a repo with no deploy watch (skills PR#55).
"$SK/merge-slot.sh" check "$REPO" "$TOKEN" || { TOKEN=""; final "NOT MERGED this run's merge slot was taken over (paused past the stale limit?) — re-run from --dry-run" 1; }
WATCH=0; case "${REPO#*/}" in NetPilot-2-Backend|NetPilot-2-LB|NetPilot-2-Frontend|netpilot-marketing) WATCH=1;; esac
KEEP=1
gh pr merge "$PR" -R "$REPO" --squash --delete-branch --match-head-commit "$HEAD" > /tmp/merge-out.$$ 2>&1; rc=$?
cat /tmp/merge-out.$$; rm -f /tmp/merge-out.$$
if [ $rc -ne 0 ]; then
  st=$(gh pr view "$PR" -R "$REPO" --json state --jq .state 2>/dev/null)
  case "$st" in
    OPEN|CLOSED) KEEP=0; final "NOT MERGED gh pr merge rc=$rc (state=$st)" 1;;
    MERGED) echo "merge.sh: gh pr merge rc=$rc but the PR reads MERGED — continuing";;
    *) final "BROKEN gh pr merge rc=$rc and the PR state is unreadable ('$st') — read it by hand; the merge slot stays held" 2;;
  esac
fi
MSTATE=""; MOID=""
for i in 1 2 3 4 5 6 7 8; do
  st=$(gh pr view "$PR" -R "$REPO" --json state,mergeCommit --jq '"\(.state) \(.mergeCommit.oid // "")"' 2>/dev/null)
  read -r MSTATE MOID <<< "$st"
  [ "$MSTATE" = "MERGED" ] && [ "${#MOID}" = 40 ] && break
  sleep 5
done
[ "$MSTATE" = "MERGED" ] || final "BROKEN merge command returned 0 but state=$MSTATE" 2
[ "${#MOID}" = 40 ] || final "BROKEN merged but no 40-char merge oid after 40 s — read it by hand" 2
[ $WATCH = 1 ] && { "$SK/merge-slot.sh" sha "$REPO" "$TOKEN" "$MOID"; echo "merge.sh: merge slot for $REPO stays held until \`postmerge.sh ${REPO#*/} $MOID\` ends clean (merge-slot.sh)"; }
MP1=$(gh api "repos/$REPO/commits/$MOID" --jq '.parents[0].sha' 2>/dev/null)
# a base that moved inside the window keeps the slot in EVERY repo (the sha recorded, so postmerge.sh can settle it): in a
# no-watch repo too, nothing else merges until main is verified (Codex, skills PR#60)
[ "$MP1" = "$TIP2" ] || { [ $WATCH = 0 ] && "$SK/merge-slot.sh" sha "$REPO" "$TOKEN" "$MOID"; echo "merge.sh: WARNING — merge commit's parent ${MP1:0:10} != the base tip checked seconds earlier ${TIP2:0:10}: main advanced inside the window; verify main's CI / revert per deploy.md — the merge slot stays held until \`postmerge.sh ${REPO#*/} $MOID\`"; final "BROKEN merged onto a base that moved inside the window; merge oid $MOID" 2; }
[ $WATCH = 0 ] && { KEEP=0; MERGED=1; }   # proven merged on the checked base, no deploy watch to wait for: released at exit — and an acknowledged hold with it
final "MERGED $MOID" 0
}
main "$@"
