#!/usr/bin/env bash
# lane-audit.sh <owner/repo> <issue>… [pr:<n>…] | <owner/repo> -f <file with one issue number per line>
# An issue-less (session-owned) lane is audited by its PR: `pr:<n>` prints the PR row without an issue column.
# One row per issue, so a coordinator sees in ONE read whether a delegated lane really finished (SKILL.md step 11):
#   issue state · its linked PR(s) (closing references + every PR whose body mentions #N, tagged `mention`) and their state · the merge sha ·
#   whether NetPilot-Claude/worktrees/<repo>/<branch> still exists · whether the LOCAL branch still exists in the main checkout
#   (`git worktree remove` leaves it) · whether the remote branch still exists · the
#   postmerge RESULT the merge slot recorded for that sha (merge-slot.sh keeps a holder only while a watch runs or
#   ended non-clean; "slot free" after a clean watch).
# Exit 0 when every row is settled; 1 when anything is still open (issue, PR, worktree, remote branch, a held slot).
# Why (Lin, 2026-10-04): board 31's 14 lanes reported "done" with 3 worktrees, 2 remote branches and one unmerged
# PR left behind; each was found by hand, one per report.
main() {
set -uo pipefail
repo=${1:?usage: lane-audit.sh <owner/repo> <issue>… | -f <file>}; shift
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "lane-audit.sh: '$repo' is not owner/repo" >&2; exit 2; }
issues=()
if [ "${1:-}" = -f ]; then while read -r i; do issues+=("$i"); done < <(grep -oE '[0-9]+' "${2:?file}"); else issues=("$@"); fi   # bash 3.2: no mapfile
[ ${#issues[@]} -gt 0 ] || { echo "lane-audit.sh: no issue numbers (or pr:<n>)" >&2; exit 2; }
S=$(cd "$(dirname "$0")" && pwd); ws=$(cd "$S/../../../.." && pwd); [ -d "$ws/NetPilot-2-Backend/.git" ] || ws=$(cd "$ws/.." && pwd); ws=${WORKSPACE:-$ws}
owner=${repo%%/*}; name=${repo##*/}
# every GitHub call is bounded (a stalled gh would otherwise hold the audit forever): timeout, gtimeout, else a perl alarm
if command -v timeout >/dev/null 2>&1; then bounded() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then bounded() { gtimeout "$@"; }
else bounded() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV or exit 127' "$s" "$@"; }; fi
ghb() { bounded 60 gh "$@"; }
dir=${MERGE_CLAIM_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/netpilot-merge-claims}
open=0
printf '%-8s %-7s %-46s %-10s %-7s %-10s %-9s %-9s %s\n' ISSUE STATE PR BRANCH-WT LOCAL REMOTE SLOT MERGE RESULT
for n in "${issues[@]}"; do lbl="#$n"
  if [[ "$n" =~ ^pr:([0-9]+)$ ]]; then lbl="$n"   # an issue-less lane: the PR itself is the row
    prs=$(ghb pr view "${BASH_REMATCH[1]}" -R "$repo" --json number,state,isDraft,headRefName,headRepository,mergeCommit 2>/dev/null \
          | jq -c --arg r "$repo" '[{number, state, isDraft, headRefName, headRepo: (.headRepository.nameWithOwner // "-"), mergeCommit: (.mergeCommit // null), repo: $r, via: "pr"}]') \
       || { printf '%-8s %s\n' "$n" "UNREADABLE (gh pr view failed)"; open=1; continue; }
    istate="-"
  else
  j=$(ghb api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){state
        closedByPullRequestsReferences(first:100,includeClosedPrs:true){pageInfo{hasNextPage} nodes{number state isDraft headRefName headRepository{nameWithOwner} mergeCommit{oid} repository{nameWithOwner}}}}}}' \
        -f o="$owner" -f r="$name" -F n="$n" 2>/dev/null) || { printf '%-8s %s\n' "$lbl" "UNREADABLE (gh api failed)"; open=1; continue; }
  istate=$(jq -r '.data.repository.issue.state // "MISSING"' <<< "$j")
  [ "$(jq -r '.data.repository.issue.closedByPullRequestsReferences.pageInfo.hasNextPage' <<< "$j")" = true ] && { printf '%-8s %-7s %s\n' "$lbl" "$istate" "UNREADABLE (over 100 linked PRs — audit by hand)"; open=1; continue; }
  prs=$(jq -c '[(.data.repository.issue.closedByPullRequestsReferences.nodes // [])[] | . + {repo: .repository.nameWithOwner, headRepo: (.headRepository.nameWithOwner // "-")}]' <<< "$j")   # a closer may live in another repo
  # ALWAYS also the body search (a replacement PR that only mentions #N), merged with the closing references, deduped by number
  more=$(ghb pr list -R "$repo" --state all --search "#$n in:body" --json number,state,isDraft,headRefName,headRepository,mergeCommit --limit 100 2>/dev/null \
         | jq -c --arg r "$repo" 'if length >= 100 then error("over 100 matches") else [.[] | {number, state, isDraft, headRefName, headRepo: (.headRepository.nameWithOwner // "-"), mergeCommit: (.mergeCommit // null), repo: $r}] end') \
     || { printf '%-8s %-7s %s\n' "$lbl" "$istate" "UNREADABLE (PR search failed — not an empty result)"; open=1; continue; }   # fail closed
  prs=$(jq -c -n --argjson a "$prs" --argjson b "$more" '($a | map(. + {via:"closes"})) + ($b | map(. + {via:"mention"})) | unique_by(.repo, .number)')
  [ "$istate" = CLOSED ] || open=1
  fi
  if [ "$(jq length <<< "$prs")" = 0 ]; then printf '%-8s %-7s %-46s %-10s %-7s %-10s %-9s %-9s %s\n' "$lbl" "$istate" "no PR linked" - - - - - "-"; [ "$istate" = CLOSED ] || open=1; continue; fi
  while IFS=$'\t' read -r pn pstate draft branch sha via prepo headrepo; do
    [ "$sha" = - ] && sha=""; pname=${prepo##*/}; hf="$dir/${prepo/\//__}/holder"   # local checkout and merge slot belong to the PR base repository
    pcol="#$pn $pstate"; [ "$prepo" != "$repo" ] && pcol="$prepo#$pn $pstate"; [ "$draft" = true ] && pcol="$pcol/draft"; [ "$via" = mention ] && pcol="${pcol} (mention)"; [ "$pstate" = OPEN ] && open=1   # CLOSED = superseded, not a leftover
    folder=$pname; [ "$folder" = TopoViewer ] && folder=topoViewer   # GitHub casing differs from the local checkout/worktree alias
    wt="$ws/worktrees/$folder/$branch"; if [ -d "$wt" ]; then wtcol=PRESENT; open=1; else wtcol=none; fi
    co="$ws/$folder"; [ "$pname" = netpilot-skills ] && co="$ws/.claude/skills"   # the main checkout holds the local branch
    if [ -d "$co/.git" ] && git -C "$co" show-ref --verify --quiet "refs/heads/$branch"; then lcol=EXISTS; open=1; else lcol=none; fi
    # The remote branch belongs to headRepository, including fork PRs.
    # a GraphQL ref lookup: slashes in a branch name stay inside the argument (a REST path would split on them); null = gone,
    # a failed call = UNREADABLE (never "gone")
    if [[ ! "$headrepo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
      rcol=UNREADABLE; open=1
    else
    hpo=${headrepo%%/*}; hpname=${headrepo##*/}
    ref=$(ghb api graphql -f query='query($o:String!,$r:String!,$b:String!){repository(owner:$o,name:$r){ref(qualifiedName:$b){name}}}' \
          -f o="$hpo" -f r="$hpname" -f b="refs/heads/$branch" --jq '.data.repository.ref.name // "NULL"' 2>/dev/null); brc=$?
    if [ $brc != 0 ]; then rcol=UNREADABLE; open=1; elif [ "$ref" = NULL ]; then rcol=gone; else rcol=EXISTS; open=1; fi
    fi
    scol="free"; res="-"
    if [ -f "$hf" ]; then read -r hpr hsha _ hstate < "$hf"
      if [ "$hsha" = "${sha:-x}" ] || [ "$hpr" = "$pn" ]; then scol=HELD; res="$hstate"; open=1; fi; fi
    [ "$pstate" = MERGED ] && [ "$scol" = free ] && res="no hold recorded (clean watch, or never watched)"
    printf '%-8s %-7s %-46s %-10s %-7s %-10s %-9s %-9s %s\n' "$lbl" "$istate" "$pcol ($branch)" "$wtcol" "$lcol" "$rcol" "$scol" "${sha:0:7}" "$res"
  done < <(jq -r '.[] | [.number, .state, (.isDraft // false), .headRefName, (.mergeCommit.oid // "-"), .via, .repo, (.headRepo // "-")] | @tsv' <<< "$prs")   # "-" not "": read collapses an empty tab field
done
if [ $open = 0 ]; then echo "lane-audit: all settled"; else echo "lane-audit: OPEN items above (issue, PR, worktree, local or remote branch, or held slot)"; fi
exit $open
}
main "$@"
