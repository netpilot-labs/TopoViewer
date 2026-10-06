#!/usr/bin/env bash
# loose-ends.sh [--mine <text>]… [--issues <owner/repo#n>…] [--project <N>|<owner>/<N>]… [--scratch <dir>] [--cloud]
# The sweep that ends ANY agent-led work (SKILL.md step 11): one run, from anywhere, lists what is left behind on this
# machine and on GitHub. READ-ONLY — it deletes, closes, kills and fetches nothing; it prints. One line per finding,
# grouped, each ending in a suggested disposition word:
#   CLEAN          safe to clean up now (a merged-PR branch at that PR's head, an empty dir, a behind-only main)
#   MINE?          the caller says whether this session created it: yes → finish or clean it, no → raise it
#   OTHER-SESSION  live work this session did not create (an open PR / worktree / process, loop-owned or active in the
#                  last RECENT_H=48 hours) — never touched, reported as "other session's, left alone"
#   ASK-LIN        unmerged work, a stash, anything irreversible — raised to Lin with a one-line recommendation
# `--mine <text>` (repeatable): a line containing <text> (your branch, `PR #n`, your worktree) reads MINE?, never OTHER-SESSION.
# Sources:
#   local     every git repo under the workspace root (depth ≤ 3; node_modules and worktrees/ skipped): uncommitted
#             files · stashes · long-lived branches ahead of / behind origin (read with `git ls-remote`, so a stale
#             local ref cannot hide it) · extra worktrees · every other local branch tagged MERGED / OPEN-PR / CLOSED-PR /
#             NO-PR by `gh pr list --state all --head <branch>` — a squash merge leaves the branch "ahead", so ancestry
#             alone never decides; MERGED reads CLEAN only when the tip IS that PR's head (or is contained in it or in
#             the default branch). Long-lived = the origin default, main, development, customizations, and a branch
#             tracking another remote (upstream/*).
#   worktrees/  empty directories (below the per-repo container) and directories no repo has registered as a worktree
#   remote    per repo whose origin is one of LOOSE_ENDS_OWNERS (default: lz-networks netpilot-labs): open PRs not by
#             Renovate/Dependabot (author, labels, age, head) · remote branches with no open PR (default / long-lived /
#             bot / upstream-mirror branches skipped; over REMOTE_MAX=15 in one repo = one summary line)
#   board     --issues / --project: every named issue, and every board item, that is still open
#   machine   pr-gates.sh / ci-wait.sh / postmerge.sh / fleet-drive.sh processes · merge-slot holds · the DB lock ·
#             --scratch <dir> over SCRATCH_MB=5
#   cloud     only with --cloud, project netpilot-ai: golden-setup-* instances · *preupgrade* snapshots · golden images
#             outside the netpilot-golden family
# Exit: 0 nothing found · 1 findings · 2 a source could not be read (an UNREADABLE line — never a clean sweep) or usage.
# Why (Lin, 2026-10-05): a project closed "clean" still left August stashes, merged-PR check branches in three repos,
# branches of PRs merged in June, empty worktree dirs and a 43 MB scratch folder nobody had told him about — and other
# sessions' open PRs and watchers that only LOOKED like orphans. The sweep had been run by hand, three times.
main() {
set -uo pipefail
# `git status` here never rewrites an index another session is using; a partial clone never demand-fetches a missing object
export GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_NO_LAZY_FETCH=1
RECENT_H=${RECENT_H:-48}; REMOTE_MAX=${REMOTE_MAX:-15}; SCRATCH_MB=${SCRATCH_MB:-5}
OWNERS=${LOOSE_ENDS_OWNERS:-lz-networks netpilot-labs}; LONG="main development customizations"; PROJECT=netpilot-ai
mine=""; issues=""; projects=""; scratch=""; cloud=0
while [ $# -gt 0 ]; do case "$1" in
  --mine) mine="$mine${2:?--mine <text>}"$'\n'; shift 2;;
  --issues) shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do issues="$issues $1"; shift; done;;
  --project) projects="$projects ${2:?--project <N>}"; shift 2;;
  --scratch) scratch=${2:?--scratch <dir>}; shift 2;;
  --cloud) cloud=1; shift;;
  -h|--help) sed -n '2,31p' "$0"; exit 0;;
  *) echo "loose-ends.sh: unknown arg '$1'" >&2; exit 2;;
esac; done
for t in git gh jq perl; do command -v $t >/dev/null 2>&1 || { echo "loose-ends.sh: $t is not installed — nothing swept" >&2; exit 2; }; done
S=$(cd "$(dirname "$0")" && pwd); ws=$(cd "$S/../../../.." && pwd); [ -d "$ws/NetPilot-2-Backend/.git" ] || ws=$(cd "$ws/.." && pwd)
ws=${WORKSPACE:-$ws}; ws=$(cd "$ws" 2>/dev/null && pwd -P) || { echo "loose-ends.sh: workspace root not found" >&2; exit 2; }
# every network call is bounded: timeout, gtimeout, else a perl alarm (macOS ships neither of the first two)
if command -v timeout >/dev/null 2>&1; then bounded() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then bounded() { gtimeout "$@"; }
else bounded() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV or exit 127' "$s" "$@"; }; fi
ghb() { bounded 60 gh "$@"; }
now=$(date +%s); n_clean=0; n_mine=0; n_other=0; n_ask=0; unread=0; grp=0; gname=""; sink=out; rbuf=""; reg=""; prcache=""
mtime() { perl -e 'my @s = stat($ARGV[0]); print(@s ? $s[9] : 0)' "$1"; }
day() { [ "${1:-0}" -gt 0 ] 2>/dev/null && perl -MPOSIX -e 'print strftime("%Y-%m-%d", localtime($ARGV[0]))' "$1" || printf '?'; }
recent() { [ "${1:-0}" -gt 0 ] 2>/dev/null && [ $(( (now - $1) / 3600 )) -lt "$RECENT_H" ]; }
iso2epoch() { perl -MTime::Local -e '$_ = shift // ""; if (/^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?/) { my $t = timegm($6, $5, $4, $3, $2 - 1, $1);
  if ($7 && $7 ne "Z") { my ($s, $h, $m) = $7 =~ /([+-])(\d\d):?(\d\d)/; $t -= ($s eq "-" ? -1 : 1) * ($h * 3600 + $m * 60) } print $t } else { print 0 }' "${1:-}"; }
emit() { if [ "$sink" = remote ]; then rbuf="$rbuf$1"$'\n'; else printf '%s\n' "$1"; grp=$((grp+1)); fi; }
f() {   # f <DISPOSITION> <text>
  local d=$1 t=$2 m
  if [ "$d" = OTHER-SESSION ] && [ -n "$mine" ]; then
    while IFS= read -r m; do [ -n "$m" ] && case "$t" in *"$m"*) d='MINE?';; esac; done <<< "$mine"; fi
  case "$d" in CLEAN) n_clean=$((n_clean+1));; 'MINE?') n_mine=$((n_mine+1));; OTHER-SESSION) n_other=$((n_other+1));; *) n_ask=$((n_ask+1));; esac
  emit "  $t → $d"
}
unreadable() { unread=$((unread+1)); emit "  UNREADABLE  $1"; }
group() { [ -n "$gname" ] && [ "$grp" = 0 ] && echo "  (nothing)"; gname=$1; grp=0; [ -z "$1" ] || echo "== $1"; }
slug_of() { local u; u=$(git -C "$1" remote get-url origin 2>/dev/null) || return 0
  case "$u" in *github.com[:/]*) u=${u#*github.com}; u=${u#[:/]}; u=${u%/}; echo "${u%.git}";; esac; }
is_ours() { local x; for x in $OWNERS; do [ "$x" = "${1%%/*}" ] && return 0; done; return 1; }
is_long() { local x; for x in $def $LONG; do [ "$x" = "$1" ] && return 0; done; return 1; }   # $def: the caller's repo default
has_line() { [ -n "$2" ] && grep -qxF -- "$1" <<< "$2"; }
listable() { [ ! -e "$1" ] || ls "$1" >/dev/null 2>&1 || { unreadable "$1 cannot be listed — $2 NOT checked"; return 1; }; }   # absent = nothing there

pr_of() {   # <slug> <branch> <tip> → P_STATE (OPEN|MERGED|CLOSED|NONE) P_NUM P_OID P_AGEH P_LOOP P_NMERGED; 1 = unreadable
  local key="$1 $2 $3" hit j
  hit=$(awk -F'\t' -v k="$key" '$1 == k { print; exit }' <<< "$prcache")
  if [ -z "$hit" ]; then
    j=$(ghb pr list -R "$1" --state all --head "$2" --limit 50 --json number,state,headRefOid,updatedAt,isCrossRepository,labels 2>/dev/null) || return 1
    # an open PR wins; then the merged PR whose head IS this tip; then the newest merged; then the newest closed
    hit=$(jq -r --arg k "$key" --arg tip "$3" '[.[] | select(.isCrossRepository | not)] as $p | ($p | map(select(.state == "MERGED")) | length) as $nm
      | (($p | map(select(.state == "OPEN")) | .[0]) // ($p | map(select(.state == "MERGED" and .headRefOid == $tip)) | .[0])
         // ($p | map(select(.state == "MERGED")) | sort_by(.updatedAt) | last) // ($p | map(select(.state == "CLOSED")) | sort_by(.updatedAt) | last))
      | if . then [$k, .state, .number, .headRefOid, (((now - (.updatedAt | fromdateiso8601)) / 3600) | floor), (if any(.labels[].name; startswith("origin/")) then 1 else 0 end), $nm]
        else [$k, "NONE", "-", "-", "-", 0, 0] end | @tsv' <<< "$j" 2>/dev/null) || return 1
    [ -n "$hit" ] || return 1; prcache="$prcache$hit"$'\n'
  fi
  IFS=$'\t' read -r _ P_STATE P_NUM P_OID P_AGEH P_LOOP P_NMERGED <<< "$hit"
}

classify() {   # <repo dir> <slug> <ours 0|1> <branch> <tip> <local|remote> → C_TAG C_DISP C_CT; 1 = PR lookup unreadable
  local r=$1 slug=$2 ours=$3 b=$4 tip=$5 where=$6 none="NO-PR"
  # contained in the default branch? proven on origin's CURRENT tip: locally when this checkout has that commit ($defref),
  # else by GitHub's own count of commits beyond it (a checkout that is merely behind still gets its proof)
  in_default() { { [ -n "$defref" ] && git -C "$r" merge-base --is-ancestor "$tip" "$defref" 2>/dev/null; } \
    || { [ "$ours" = 1 ] && [ "$rok" = 1 ] && [ "$(ghb api "repos/$slug/compare/$def...$tip" --jq .ahead_by 2>/dev/null)" = 0 ]; }; }
  C_CT=$(git -C "$r" log -1 --format=%ct "$tip" 2>/dev/null); C_CT=${C_CT:-0}
  P_STATE=NONE; P_LOOP=0
  if [ "$b" = "(detached)" ]; then none="detached HEAD, no branch"
  elif [ "$ours" = 1 ]; then pr_of "$slug" "$b" "$tip" || return 1; else none="no PR lookup (origin not ours)"; fi
  if [ "$C_CT" = 0 ] && [ "$ours" = 1 ] && [ "$P_STATE" != MERGED ]; then   # a remote tip this checkout never fetched
    C_CT=$(iso2epoch "$(ghb api "repos/$slug/commits/$tip" --jq .commit.committer.date 2>/dev/null)"); fi
  case "$P_STATE" in
    OPEN) C_TAG="OPEN-PR #$P_NUM (updated ${P_AGEH}h ago$([ "$P_LOOP" = 1 ] && echo ', loop-owned'))"
      if [ "$P_LOOP" = 1 ] || [ "$P_AGEH" -lt "$RECENT_H" ]; then C_DISP=OTHER-SESSION; else C_DISP=ASK-LIN; fi;;
    MERGED)   # CLEAN only on proof that nothing sits beyond the merge — and never for a branch PRs keep merging FROM
      if [ "$P_NMERGED" -gt 1 ]; then C_TAG="MERGED #$P_NUM — the head of $P_NMERGED merged PRs (a long-lived branch?)"; C_DISP=ASK-LIN
      elif [ "$tip" = "$P_OID" ] || { git -C "$r" cat-file -e "$P_OID^{commit}" 2>/dev/null && git -C "$r" merge-base --is-ancestor "$tip" "$P_OID" 2>/dev/null; } || in_default; then
        C_TAG="MERGED #$P_NUM"; C_DISP=CLEAN
      else C_TAG="MERGED #$P_NUM — but tip ${tip:0:7} is NOT that PR's head ${P_OID:0:7} (commits beyond the merge?)"; C_DISP=ASK-LIN; fi;;
    *) [ "$P_STATE" = CLOSED ] && none="CLOSED-PR #$P_NUM (closed unmerged)"
      C_TAG="$none, last commit $(day "$C_CT")"
      if [ "$where" = local ] && in_default; then C_TAG="$C_TAG, nothing beyond $def"; C_DISP=CLEAN   # a remote branch may be a deploy ref: never CLEAN unproven
      elif recent "$C_CT"; then C_DISP='MINE?'; else C_DISP=ASK-LIN; fi;;
  esac
}

sweep_repo() {
  local r=$1 name slug ours=0 out rok=0 rdef="" rheads="" cur st n new d b L R T up ahead behind ct wl i covered="" wpath whead wbranch wprun rel wn wi gd act a prs heads ups cand nc tip pn pa pl pd pu ph pdraft ploop rows ups uo
  name=${r#"$ws"/}; slug=$(slug_of "$r"); [ -n "$slug" ] && is_ours "$slug" && ours=1
  cur=$(git -C "$r" branch --show-current 2>/dev/null)
  if [ $ours = 1 ]; then   # origin's default branch + every head in ONE read-only call (no fetch: no local ref moves)
    if out=$(bounded 60 git -C "$r" ls-remote --symref origin HEAD 'refs/heads/*' 2>/dev/null); then rok=1
      rdef=$(sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p' <<< "$out" | head -1)
      rheads=$(awk '$1 != "ref:" && $2 ~ /^refs\/heads\// { print substr($2, 12) "\t" $1 }' <<< "$out")
    else unreadable "$name: git ls-remote origin failed — behind-count and remote branches NOT checked"; fi
  fi
  def=$rdef; [ -n "$def" ] || def=$(git -C "$r" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'); def=${def:-main}
  # "contained in the default branch" is proven only against origin's CURRENT tip (a stale local ref survives a force-push):
  # the tip ls-remote just read, when this checkout has that commit; a third-party clone has only its tracking ref
  defref=""
  if [ $rok = 1 ]; then defref=$(awk -F'\t' -v b="$def" '$1 == b { print $2 }' <<< "$rheads"); git -C "$r" cat-file -e "${defref:-x}^{commit}" 2>/dev/null || defref=""
  elif [ $ours = 0 ]; then defref=$(git -C "$r" rev-parse -q --verify "refs/remotes/origin/$def" 2>/dev/null); fi

  # uncommitted files
  if st=$(git -C "$r" status --porcelain --untracked-files=normal 2>/dev/null); then   # explicit: status.showUntrackedFiles=no must not hide a file
    if [ -n "$st" ]; then n=$(grep -c . <<< "$st")
      new=$(git -C "$r" status --porcelain --untracked-files=normal -z 2>/dev/null | R="$r" perl -0 -ne 'chomp; next if length($_) < 4; my @s = lstat("$ENV{R}/" . substr($_, 3)); $m = $s[9] if @s && $s[9] > ($m // 0); END { print $m // 0 }')
      d=ASK-LIN; recent "$new" && d='MINE?'
      f "$d" "$name: $n uncommitted file(s) on ${cur:-a detached HEAD}, newest $(day "$new"): $(head -3 <<< "$st" | cut -c4- | tr '\n' ' ')"; fi
  else unreadable "$name: git status failed"; fi
  [ -n "$cur" ] || f 'MINE?' "$name: the main checkout is on a detached HEAD ($(git -C "$r" rev-parse --short HEAD 2>/dev/null))"
  # stashes
  rows=$(git -C "$r" stash list --format='%gd%x09%cs%x09%gs' 2>/dev/null) || unreadable "$name: git stash list failed — stashes NOT checked"
  while IFS=$'\t' read -r a b ct; do [ -n "$a" ] && f ASK-LIN "$name: $a ($b) $ct"; done <<< "$rows"
  # long-lived branches vs origin
  for b in $(printf '%s\n' "$def" $LONG | awk '!s[$0]++'); do
    L=$(git -C "$r" rev-parse -q --verify "refs/heads/$b" 2>/dev/null) || continue
    up=$(git -C "$r" for-each-ref --format='%(upstream:short)' "refs/heads/$b"); case "$up" in ""|origin/*) ;; *) continue;; esac
    T=$(git -C "$r" rev-parse -q --verify "refs/remotes/origin/$b" 2>/dev/null); R=$T
    if [ $rok = 1 ]; then R=$(awk -F'\t' -v b="$b" '$1 == b { print $2 }' <<< "$rheads")
      [ -n "$R" ] || { f ASK-LIN "$name: long-lived branch $b exists here but not on origin"; continue; }; fi
    if [ -z "$R" ]; then [ $ours = 1 ] && continue   # ours with origin unread: the UNREADABLE line above already says so
      f ASK-LIN "$name: long-lived branch $b has no origin/$b in this checkout (never pushed?)"; continue; fi
    [ "$L" = "$R" ] && continue
    if git -C "$r" cat-file -e "$R^{commit}" 2>/dev/null; then ahead=$(git -C "$r" rev-list --count "$R..$L"); behind=$(git -C "$r" rev-list --count "$L..$R")
    else behind="?"; ahead="?"; [ -n "$T" ] && ahead=$(git -C "$r" rev-list --count "$T..$L"); fi   # origin's tip is not in this checkout
    if [ "$ahead" != 0 ]; then ct=$(git -C "$r" log -1 --format=%ct "$L"); d=ASK-LIN; recent "$ct" && d='MINE?'
      f "$d" "$name: $b is $ahead commit(s) AHEAD of origin/$b (unpushed; $behind behind), last commit $(day "$ct")"
    elif [ $rok != 1 ]; then :
    elif [ "$behind" = "?" ]; then f CLEAN "$name: $b — origin/$b moved to ${R:0:7}, not fetched here (git pull --ff-only: it refuses unless that is a fast-forward)"
    else f CLEAN "$name: $b is $behind commit(s) behind origin/$b (git pull --ff-only)"; fi
  done
  # extra worktrees (the first block is the main checkout)
  wl=$(git -C "$r" worktree list --porcelain 2>/dev/null) || { unreadable "$name: git worktree list failed"; wl=""; }
  i=0
  while IFS=$'\t' read -r wpath whead wbranch wprun; do
    [ -n "$wpath" ] || continue; i=$((i+1)); reg="$reg$wpath"$'\n'; [ $i = 1 ] && continue
    rel=${wpath#"$ws"/}
    if [ ! -d "$wpath" ]; then f CLEAN "$name: worktree $rel [$wbranch] is registered but its directory is gone (git worktree prune)"; continue; fi
    [ "$wbranch" = "(detached)" ] || covered="$covered$wbranch"$'\n'
    st=$(git -C "$wpath" status --porcelain --ignored --untracked-files=normal 2>/dev/null) || { unreadable "$name: worktree $rel [$wbranch] — git status failed"; continue; }
    wn=$(grep -c '^[^!]' <<< "$st"); wi=$(grep -c '^!!' <<< "$st"); gd=$(git -C "$wpath" rev-parse --absolute-git-dir 2>/dev/null)
    classify "$r" "$slug" $ours "$wbranch" "$whead" local || { unreadable "$name: worktree $rel [$wbranch] — PR lookup failed (gh)"; continue; }
    act=$C_CT; for a in "$gd/logs/HEAD" "$gd/index"; do a=$(mtime "$a"); [ "$a" -gt "$act" ] && act=$a; done
    d=$C_DISP; [ "$d" = CLEAN ] && [ "$wn" -gt 0 ] && d=ASK-LIN   # uncommitted files are unmerged work
    # ignored files (.env, a run folder) exist ONLY here and `git worktree remove` deletes them: never CLEAN, the caller says
    [ "$d" = CLEAN ] && [ "$wi" -gt 0 ] && d='MINE?'
    if recent "$act"; then case "$d" in CLEAN) d='MINE?';; 'MINE?'|ASK-LIN) d=OTHER-SESSION;; esac; fi   # a live worktree is somebody's
    f "$d" "$name: worktree $rel [$wbranch] $C_TAG, $wn uncommitted, $wi ignored path(s)$([ "$wi" -gt 0 ] && echo " ($(grep '^!!' <<< "$st" | head -3 | cut -c4- | tr '\n' ' ' | sed 's/ $//'))"), last activity $(day "$act")"
  done < <(awk 'BEGIN { RS = ""; FS = "\n" } { p = ""; h = "-"; b = "(detached)"; pr = 0
      for (i = 1; i <= NF; i++) { if ($i ~ /^worktree /) p = substr($i, 10); else if ($i ~ /^HEAD /) h = substr($i, 6); else if ($i ~ /^branch refs\/heads\//) b = substr($i, 19); else if ($i ~ /^prunable/) pr = 1 }
      print p "\t" h "\t" b "\t" pr }' <<< "$wl")
  # every other local branch
  rows=$(git -C "$r" for-each-ref --format='%(refname:short)%09%(objectname)%09%(if)%(upstream:short)%(then)%(upstream:short)%(else)-%(end)' refs/heads 2>/dev/null) \
    || unreadable "$name: git for-each-ref failed — local branches NOT checked"
  while IFS=$'\t' read -r b tip up; do
    [ -n "$b" ] || continue
    case "$up" in -|origin/*) ;; *)   # tracks another remote (upstream/*): a mirror branch — unless it carries commits that remote lacks
      a=$(git -C "$r" rev-list --count "$up..$tip" 2>/dev/null); [ "${a:-?}" = 0 ] && continue
      ct=$(git -C "$r" log -1 --format=%ct "$tip" 2>/dev/null); d=ASK-LIN; recent "${ct:-0}" && d='MINE?'
      f "$d" "$name: branch $b tracks $up and is ${a:-?} commit(s) ahead of it (unpushed), last commit $(day "${ct:-0}")"; continue;;
    esac
    is_long "$b" && continue
    has_line "$b" "$covered" && continue              # reported on its worktree line
    if classify "$r" "$slug" $ours "$b" "$tip" local; then
      f "$C_DISP" "$name: branch $b$([ "$b" = "$cur" ] && echo ' (checked out in the main checkout)') $C_TAG"
    else unreadable "$name: branch $b — PR lookup failed (gh)"; fi
  done <<< "$rows"

  # remote: open PRs, then remote branches no open PR explains
  [ $ours = 1 ] || { rskip="$rskip $name"; return 0; }
  sink=remote
  prs=$(ghb pr list -R "$slug" --state open --limit 200 --json number,author,labels,createdAt,updatedAt,headRefName,isDraft,isCrossRepository 2>/dev/null) \
    && n=$(jq 'length' <<< "$prs" 2>/dev/null) && [ -n "$n" ] && [ "$n" -lt 200 ] \
    || { unreadable "$slug: gh pr list failed (or 200+ open PRs) — open PRs and remote branches NOT checked"; sink=out; return 0; }
  rows=$(jq -r '.[] | select(((.author.login // "ghost") | test("renovate|dependabot"; "i") | not) and (.headRefName | test("^(renovate|dependabot)/") | not))
      | [.number, (.author.login // "ghost"), (([.labels[].name] | join(",")) | if . == "" then "-" else . end), (((now - (.createdAt | fromdateiso8601)) / 86400) | floor),
         (((now - (.updatedAt | fromdateiso8601)) / 3600) | floor), .headRefName, .isDraft, any(.labels[].name; startswith("origin/"))] | @tsv' <<< "$prs" 2>/dev/null) \
    && heads=$(jq -r '.[] | select(.isCrossRepository | not) | .headRefName' <<< "$prs" 2>/dev/null) \
    || { unreadable "$slug: the open-PR list could not be parsed — open PRs and remote branches NOT checked"; sink=out; return 0; }
  while IFS=$'\t' read -r pn pa pl pd pu ph pdraft ploop; do
    [ -n "$pn" ] || continue; d=ASK-LIN; { [ "$ploop" = true ] || [ "$pu" -lt "$RECENT_H" ]; } && d=OTHER-SESSION
    f "$d" "$slug: PR #$pn by $pa [$pl] opened ${pd}d ago, updated ${pu}h ago, head $ph$([ "$pdraft" = true ] && echo ', draft')$([ "$ploop" = true ] && echo ', loop-owned')"
  done <<< "$rows"
  if [ $rok = 1 ]; then
    cand=""; nc=0; ups=""; uo=""   # a fork: upstream's CURRENT heads (ls-remote, not the local tracking refs)
    if uo=$(git -C "$r" remote get-url upstream 2>/dev/null) && [[ "$uo" == *github.com[:/]* ]]; then uo=${uo#*github.com}; uo=${uo#[:/]}; uo=${uo%%/*}
      ups=$(bounded 60 git -C "$r" ls-remote --heads upstream 2>/dev/null | awk '{ print substr($2, 12) "\t" $1 }'); fi
    while IFS=$'\t' read -r b tip; do
      [ -n "$b" ] || continue; is_long "$b" && continue
      case "$b" in renovate/*|dependabot/*|gh-pages) continue;; esac
      has_line "$b" "$heads" && continue   # an open PR's head: listed above
      # a fork's mirror branch: upstream's current tip is the same, or GitHub counts 0 commits on origin's branch beyond it
      up=""; [ -n "$ups" ] && up=$(awk -F'\t' -v b="$b" '$1 == b { print $2 }' <<< "$ups")
      [ -n "$up" ] && { [ "$up" = "$tip" ] || [ "$(ghb api "repos/$slug/compare/$uo:$b...$b" --jq .ahead_by 2>/dev/null)" = 0 ]; } && continue
      cand="$cand$b"$'\t'"$tip"$'\n'; nc=$((nc+1))
    done <<< "$rheads"
    if [ $nc -gt "$REMOTE_MAX" ]; then f ASK-LIN "$slug: $nc remote branches with no open PR (over $REMOTE_MAX — not looked up one by one): $(head -5 <<< "$cand" | cut -f1 | tr '\n' ' ')…"
    else while IFS=$'\t' read -r b tip; do
        [ -n "$b" ] || continue
        if classify "$r" "$slug" 1 "$b" "$tip" remote; then [ "$P_STATE" = OPEN ] || f "$C_DISP" "$slug: remote branch $b $C_TAG"
        else unreadable "$slug: remote branch $b — PR lookup failed (gh)"; fi
      done <<< "$cand"; fi
  fi
  sink=out
}

walk() {   # <dir> <depth>: depth 1 = the per-repo containers under worktrees/ (an empty one is the layout, not a leftover)
  local d=$1 depth=$2 c p m
  listable "$d" "directories beneath it" || return 0
  for c in "$d"/* "$d"/.[!.]*; do
    [ -e "$c" ] || [ -L "$c" ] || continue; [ "${c##*/}" = .DS_Store ] && continue
    if [ -L "$c" ] || [ ! -d "$c" ]; then m=$(mtime "$c"); p='ASK-LIN'; recent "$m" && p='MINE?'; f "$p" "${c#"$ws"/}: a stray file, not a worktree ($(day "$m"))"; continue; fi
    p=$(cd "$c" 2>/dev/null && pwd -P) || { unreadable "${c#"$ws"/}: cannot enter"; continue; }
    has_line "$p" "$reg" && continue                                      # a registered worktree: swept under its repo
    if [ "$depth" = 1 ] || grep -qF -- "$p/" <<< "$reg"; then walk "$c" $((depth+1)); continue; fi   # a container, or it holds a registered worktree deeper (a branch with a slash)
    m=$(find "$c" ! -type d ! -name .DS_Store 2>/dev/null | head -1); p=$?
    if [ -z "$m" ] && [ $p != 0 ]; then unreadable "${c#"$ws"/}: could not be walked — NOT checked for files"
    elif [ -z "$m" ]; then f CLEAN "${c#"$ws"/}: empty directory (no file beneath it; rmdir)"
    else m=$(mtime "$c"); p='ASK-LIN'; recent "$m" && p='MINE?'
      f "$p" "${c#"$ws"/}: not a registered worktree of any repo ($(ls -A "$c" | wc -l | tr -d ' ') entries, modified $(day "$m")$([ -e "$c/.git" ] && echo '; has a .git — a clone, or a worktree whose registration was pruned'))"; fi
  done
}

board() {   # <N> | <owner>/<N>: every non-archived item whose issue/PR is still open (a draft item: status not Done)
  local o=lz-networks n=$1 c="" j rows ref state status title
  case "$n" in */*) o=${n%%/*}; n=${n##*/};; esac
  [[ "$n" =~ ^[0-9]+$ ]] || { unreadable "--project '$1' is not <N> or <owner>/<N>"; return; }
  while :; do
    j=$(ghb api graphql -f query='query($o:String!,$n:Int!,$c:String){repositoryOwner(login:$o){... on ProjectV2Owner{projectV2(number:$n){title
          items(first:100,after:$c){pageInfo{hasNextPage endCursor} nodes{isArchived fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}
          content{__typename ... on Issue{number state title repository{nameWithOwner}} ... on PullRequest{number state title repository{nameWithOwner}} ... on DraftIssue{title}}}}}}}}' \
        -f o="$o" -F n="$n" ${c:+-f c="$c"} 2>/dev/null) && [ -n "$(jq -r '.data.repositoryOwner.projectV2.title // empty' <<< "$j" 2>/dev/null)" ] \
      || { unreadable "board $o/$n: not readable (gh project scope? gh auth refresh -s project) — its items NOT checked"; return; }
    rows=$(jq -r '
      .data.repositoryOwner.projectV2.items.nodes[] | select(.isArchived | not) | (.fieldValueByName.name // "none") as $s | .content as $c
      | if $c == null then ["an item this login cannot read", "?", $s, ""]
        elif $c.__typename == "DraftIssue" then (if $s == "Done" then empty else ["draft item", "OPEN", $s, $c.title[0:70]] end)
        elif $c.state == "OPEN" then ["\($c.repository.nameWithOwner)#\($c.number)", "OPEN", $s, $c.title[0:70]] else empty end | @tsv' <<< "$j" 2>/dev/null) \
      || { unreadable "board $o/$n: a page of items could not be parsed — NOT checked"; return; }
    while IFS=$'\t' read -r ref state status title; do [ -n "$ref" ] && f 'MINE?' "board $n: $ref $state (status $status) $title"; done <<< "$rows"
    [ "$(jq -r '.data.repositoryOwner.projectV2.items.pageInfo.hasNextPage' <<< "$j")" = true ] || break
    c=$(jq -r '.data.repositoryOwner.projectV2.items.pageInfo.endCursor' <<< "$j")
  done
}

# ---- local + remote, one pass per repo (remote lines are held back and printed as their own group)
repos=$(find "$ws" -maxdepth 4 \( -name node_modules -o -path "$ws/worktrees" \) -prune -o -name .git \( -type d -prune -o -type f \) -print 2>&1); findrc=$?
finderr=$(grep -v '/\.git$' <<< "$repos" | head -3 | tr '\n' ' '); found=$(grep '/\.git$' <<< "$repos" | sed 's|/\.git$||' | sort); repos=""
while IFS= read -r r; do   # a `.git` FILE is a repo root too (a submodule, a separate git dir) — unless it is a linked worktree of a repo found here
  [ -n "$r" ] || continue
  if [ -f "$r/.git" ]; then a=$(git -C "$r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); has_line "${a%/.git}" "$found" && continue; fi
  repos="$repos$r"$'\n'
done <<< "$found"
[ -n "$repos" ] || { echo "loose-ends.sh: no git repo found under $ws" >&2; exit 2; }
gh_ok=1; ghb auth status --active -h github.com >/dev/null 2>&1 || gh_ok=0
echo "loose-ends: $(grep -c . <<< "$repos") repos under $ws · recent = ${RECENT_H}h · $(date '+%Y-%m-%d %H:%M %Z')"
group "local (uncommitted · stashes · ahead/behind · worktrees · branches)"
[ $gh_ok = 1 ] || unreadable "gh is not logged in (gh auth login) — every PR lookup below fails"
[ $findrc = 0 ] || unreadable "find could not walk all of $ws (rc=$findrc) — repos beneath it NOT swept: $finderr"
rskip=""
while IFS= read -r r; do [ -n "$r" ] && sweep_repo "$r"; done <<< "$repos"

group "worktrees/ (empty or unregistered directories)"
if [ -d "$ws/worktrees" ]; then walk "$ws/worktrees" 1; fi

group "remote (open PRs not by Renovate/Dependabot · branches with no open PR)"
[ -n "$rbuf" ] && { printf '%s' "$rbuf"; grp=1; }
[ -n "$rskip" ] && echo "  note: origin not ours, remote not swept:$rskip"

if [ -n "$issues$projects" ]; then
  group "board (issues and board items still open)"
  for a in $issues; do
    if [[ "$a" =~ ^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)$ ]]; then
      if j=$(ghb issue view "${BASH_REMATCH[2]}" -R "${BASH_REMATCH[1]}" --json state,title --jq '[.state, .title[0:70]] | @tsv' 2>/dev/null) && [ -n "$j" ]; then
        IFS=$'\t' read -r st ti <<< "$j"; [ "$st" = OPEN ] && f 'MINE?' "issue $a OPEN: $ti"
      else unreadable "issue $a: gh issue view failed"; fi
    else unreadable "--issues '$a' is not owner/repo#n"; fi
  done
  for a in $projects; do board "$a"; done
fi

group "machine (watchers · merge slots · DB lock · scratch)"
if psout=$(ps -axo pid=,etime=,lstart=,command= 2>/dev/null) && [ -n "$psout" ]; then
  # one line per distinct command line, shown from the script name on (the shell wrapper before it says nothing);
  # older than RECENT_H = no watch lasts that long, so it is no longer "somebody's live work"
  while IFS=$'\t' read -r cnt pid et started cmd; do
    [ -n "$pid" ] || continue; a=0; case "$et" in *-*) a=$(( 10#${et%%-*} * 24 ));; esac
    d=OTHER-SESSION; [ "$a" -ge "$RECENT_H" ] && d=ASK-LIN
    f "$d" "process $pid$([ "$cnt" -gt 1 ] && echo " (+$((cnt-1)) with the same command line)") started $started, running $et: $cmd"
  done < <(awk '/(pr-gates|ci-wait|postmerge|fleet-drive)\.sh/ && !/loose-ends\.sh/ { pid = $1; et = $2; st = $4 " " $5 " " $6; $1 = $2 = $3 = $4 = $5 = $6 = $7 = ""; sub(/^ +/, "")
      if (!($0 in c)) { order[++k] = $0; first[$0] = pid "\t" et "\t" st } c[$0]++ }
    END { for (i = 1; i <= k; i++) { cmd = order[i]; match(cmd, /[^ \/"]*(pr-gates|ci-wait|postmerge|fleet-drive)\.sh/); print c[cmd] "\t" first[cmd] "\t" (RSTART > 1 ? "… " : "") substr(cmd, RSTART, 150) } }' <<< "$psout")
else unreadable "ps failed — watcher processes NOT checked"; fi
sdir=${MERGE_CLAIM_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/netpilot-merge-claims}
listable "$sdir" "merge slots"
for s in "$sdir"/*; do
  [ -d "$s" ] || continue; hpr="?"; hsha="?"; hstate="no holder file"; a=$s; [ -f "$s/holder" ] && { a=$s/holder; read -r hpr hsha _ hstate < "$s/holder"; }
  a=$(( (now - $(mtime "$a")) / 60 )); n=${s##*/}; n=${n/__//}
  if [ "${hstate:-inflight}" = inflight ] && [ "$a" -lt 60 ]; then f OTHER-SESSION "merge slot $n held by PR #$hpr (inflight, $a min, merge ${hsha:0:10}) — its deploy watch settles it"
  else f ASK-LIN "merge slot $n held by PR #$hpr (${hstate:-inflight}, $a min, merge ${hsha:0:10}) — read that watch's result first (deploy.md); never delete a slot by hand"; fi
done
lock=${NETPILOT_DB_LOCK:-/tmp/netpilot-db.lock.d}
alive() { [ -n "$1" ] && { kill -0 "$1" 2>/dev/null || kill -0 -- "-$1" 2>/dev/null; }; }   # signal 0: a liveness read, nothing is killed
if [ -d "$lock" ]; then tg=$(cat "$lock/tag" 2>/dev/null); p1=$(cat "$lock/pid" 2>/dev/null); p2=$(cat "$lock/wrapper" 2>/dev/null)
  if alive "$p1" || alive "$p2"; then f OTHER-SESSION "DB lock $lock held by ${tg:-?} (pid ${p1:-${p2:-?}} alive)"
  elif ! [[ "$p1$p2" =~ ^[0-9]+$ ]]; then f OTHER-SESSION "DB lock $lock has no readable owner (just taken, or its pid files are unreadable) — leave it to with-db-lock.sh"
  else f CLEAN "DB lock $lock left by ${tg:-?}, its owners are gone (the next with-db-lock.sh run reclaims it — nothing to do)"; fi
fi
listable "${lock%.d}.q" "the DB lock queue"
for t in "${lock%.d}.q"/*; do [ -e "$t" ] || continue; p1=${t##*/}; p1=${p1#*.}; p1=${p1%%.*}
  if ! [[ "$p1" =~ ^[0-9]+$ ]]; then f ASK-LIN "DB lock queue: ${t##*/} is not a <time>.<pid>.<tag> ticket — with-db-lock.sh cannot parse it"
  elif alive "$((10#$p1))"; then f OTHER-SESSION "DB lock queue: ${t##*/} is waiting (pid alive)"
  else f CLEAN "DB lock queue: ticket ${t##*/} of a dead waiter (dropped by the next with-db-lock.sh poll)"; fi
done
if [ -n "$scratch" ]; then
  if [ -d "$scratch" ] && kb=$(du -sk "$scratch" 2>/dev/null | cut -f1) && [ -n "$kb" ]; then nf=$(find "$scratch" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$kb" -ge $((SCRATCH_MB * 1024)) ]; then f 'MINE?' "scratch $scratch: $((kb / 1024)) MB in $nf file(s) (over $SCRATCH_MB MB)"
    else echo "  note: scratch $scratch: $kb KB in $nf file(s) — under $SCRATCH_MB MB, not a finding"; grp=$((grp+1)); fi
  else unreadable "scratch $scratch: not a readable directory"; fi
fi

if [ $cloud = 1 ]; then
  group "cloud ($PROJECT: golden-setup-* instances · *preupgrade* snapshots · golden images outside the family)"
  if command -v gcloud >/dev/null 2>&1; then
    gcl() { bounded 90 gcloud compute "$@" --project "$PROJECT" 2>/dev/null; }
    cloud_rows() {   # <kind> <rows: name,detail,creationTimestamp> [<detail value to skip>]
      local nm det ts e d
      while IFS=, read -r nm det ts; do [ -n "$nm" ] || continue; [ -n "${3:-}" ] && [ "$det" = "$3" ] && continue
        e=$(iso2epoch "$ts"); d=ASK-LIN; recent "$e" && d=OTHER-SESSION
        f "$d" "$1 $nm ($det, created $(day "$e"))"; done <<< "$2"
    }
    if rows=$(gcl instances list --filter='name~^golden-setup-' --format='csv[no-heading](name,status,creationTimestamp)'); then cloud_rows instance "$rows"
    else unreadable "gcloud instances list failed — golden-setup-* instances NOT checked"; fi
    if rows=$(gcl snapshots list --filter='name~preupgrade' --format='csv[no-heading](name,diskSizeGb,creationTimestamp)'); then cloud_rows snapshot "$rows"
    else unreadable "gcloud snapshots list failed — *preupgrade* snapshots NOT checked"; fi
    if rows=$(gcl images list --no-standard-images --filter='name~golden' --format='csv[no-heading](name,family,creationTimestamp)'); then cloud_rows "image outside the netpilot-golden family" "$rows" netpilot-golden
    else unreadable "gcloud images list failed — golden images NOT checked"; fi
  else unreadable "gcloud is not installed — cloud NOT checked"; fi
fi
group ""   # closes the last group
total=$((n_clean + n_mine + n_other + n_ask))
if [ $unread -gt 0 ]; then echo "loose-ends: $unread source(s) UNREADABLE — NOT a clean sweep · $total finding(s): CLEAN $n_clean · MINE? $n_mine · OTHER-SESSION $n_other · ASK-LIN $n_ask"; exit 2; fi
if [ $total = 0 ]; then echo "loose-ends: nothing found"; exit 0; fi
echo "loose-ends: $total finding(s) — CLEAN $n_clean · MINE? $n_mine · OTHER-SESSION $n_other · ASK-LIN $n_ask — each one is cleaned up, closed out, or raised to Lin (SKILL.md step 11)"
exit 1
}
main "$@"
