#!/usr/bin/env bash
# merge.sh <repo> <owner> <pr> [<worktree-branch>] [--wait-codex]
# Compatibility entrypoint: canonical dev-workflow owns head/base/review/CI/slot proof.
# Every repository then runs canonical postmerge, including no-deploy push verification.
# Worktrees are retained for safe inspection and post-merge cleanup; never pre-delete.
# A workflow-only stale branch needs proven checkout ancestry or rebase/re-verification.
set -uo pipefail
main() {
  [ $# -ge 3 ] && [ $# -le 5 ] || { echo 'usage: merge.sh <repo> <owner> <pr> [<worktree-branch>] [--wait-codex]' >&2; return 2; }
  local repo=$1 owner=$2 pr=$3 worktree='' wait=0 arg
  shift 3
  for arg in "$@"; do
    case "$arg" in
      --wait-codex) [ $wait = 0 ] || return 2; wait=1;;
      --*) echo "unknown argument: $arg" >&2; return 2;;
      *) [ -z "$worktree" ] || return 2; worktree=$arg;;
    esac
  done
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+$ ]] && [[ "$owner" =~ ^[A-Za-z0-9_.-]+$ ]] && [[ "$pr" =~ ^[0-9]+$ ]] || return 2
  local skills canonical merge_output merge_rc sha
  skills="$(cd "$(dirname "$0")/../.." && pwd)" || return 2
  canonical="$skills/dev-workflow/scripts"
  for arg in merge.sh postmerge.sh pr-gates.sh; do
    [ -x "$canonical/$arg" ] || { echo "BROKEN: canonical helper missing: $canonical/$arg" >&2; return 2; }
  done
  if [ $wait = 1 ]; then
    "$canonical/pr-gates.sh" "$pr" --repo "$owner/$repo" --watch --wait-ci || return $?
  fi
  "$canonical/merge.sh" "$owner/$repo" "$pr" --dry-run || return $?
  merge_output=$("$canonical/merge.sh" "$owner/$repo" "$pr"); merge_rc=$?
  printf '%s\n' "$merge_output"
  [ $merge_rc = 0 ] || return "$merge_rc"
  sha=$(printf '%s\n' "$merge_output" | awk '$1=="merge.sh:" && $2=="FINAL" && $3=="MERGED" {print $4}')
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'BROKEN: canonical merge did not prove one full merge SHA' >&2; return 2; }
  "$canonical/postmerge.sh" "$repo" "$sha" || return $?
  [ -z "$worktree" ] || echo "worktree $worktree retained: inspect its files before the authorized post-merge cleanup"
  return 0
}
main "$@"
