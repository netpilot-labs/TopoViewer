#!/usr/bin/env bash
# revert-pr.sh — open the revert PR for a merged dependency bump (mechanics §9). Opens it
# NON-draft so the one CI run starts immediately, requests Codex, and stops: merging is
# the endpoint decision (tiers §6.2 auto-revert grant, else agent/hold).
#
# Usage: revert-pr.sh <repo> <merged-pr-number> "<signal that fired, with link>"
# Run from anywhere; the repo checkout is resolved as <workspace>/<repo>, the worktree as
# <workspace>/worktrees/<repo>/revert-<n> (dev-workflow convention).
set -euo pipefail
# Repo → GitHub owner (the fleet spans two owners; a wrong owner reads as "no alerts, no PRs,
# no dashboard" — containerlab-mcp was invisible to the pass all night, 2026-09-09).
owner_of() { case "$1" in containerlab-mcp) echo netpilot-labs;; *) echo "${OWNER:-lz-networks}";; esac; }
R=${1:?repo}; n=${2:?merged PR number}; signal=${3:?signal}; OWNER=$(owner_of "$R")
# Workspace root: WORKSPACE env, else the canonical layout (skills/<skill>/scripts -> root),
# else one level up (a consumer's vendored copy sits inside <root>/<consumer>/.claude/skills).
ws=${WORKSPACE:-$(cd "$(dirname "$0")/../../../.." && pwd)}
[ -d "$ws/$R/.git" ] || ws=$(cd "$ws/.." && pwd)
repo_dir="$ws/$R"; wt="$ws/worktrees/$R/revert-$n"
[ -d "$repo_dir/.git" ] || { echo "no checkout for $R under $ws (set WORKSPACE)" >&2; exit 2; }
sha=$(gh pr view "$n" --repo "$OWNER/$R" --json mergeCommit,state --jq 'if .state != "MERGED" then error("PR not merged") else .mergeCommit.oid end')
title=$(gh pr view "$n" --repo "$OWNER/$R" --json title --jq .title)
git -C "$repo_dir" fetch -q origin main
git -C "$repo_dir" worktree add "$wt" -b "revert-$n" origin/main
case "$R" in
  NetPilot-2-Frontend|netpilot-marketing)
    # Pin commit identity; production push actor is separately the machine identity.
    GIT_AUTHOR_NAME=lz-networks GIT_AUTHOR_EMAIL=50209324+lz-networks@users.noreply.github.com \
    GIT_COMMITTER_NAME=lz-networks GIT_COMMITTER_EMAIL=50209324+lz-networks@users.noreply.github.com \
      git -c user.name=lz-networks -c user.email=50209324+lz-networks@users.noreply.github.com \
      -C "$wt" revert --no-edit "$sha" ;;
  *) git -C "$wt" revert --no-edit "$sha" ;;
esac
case "$R" in
  NetPilot-2-Frontend|netpilot-marketing)
    env -u GH_TOKEN -u GITHUB_TOKEN git -C "$wt" push -u origin "revert-$n" ;;
  *) git -C "$wt" push -u origin "revert-$n" ;;
esac
url=$(gh pr create --repo "$OWNER/$R" --head "revert-$n" --base main \
  --title "Revert dep bump #$n: $title" \
  --body "Reverts #$n ($sha). Signal: $signal. Re-attempt trigger: recorded in the dependency-updates ledger (incident row). Endpoint: tiers.md §6.2.")
env -u GH_TOKEN -u GITHUB_TOKEN gh pr comment "$url" --body "@codex review" > /dev/null
echo "$url"
echo "next: pr-gates.sh, merge per tiers §6.2, deploy watch, incident row + watch list (learning.md rubric e)"
