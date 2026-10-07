#!/usr/bin/env bash
# dashboard.sh — Renovate Dependency Dashboard checkboxes (mechanics §5). Ticking a box
# edits the issue body; Renovate reacts within minutes. Approval OPENS a PR, never merges.
#
# Usage: dashboard.sh <repo> show
#        dashboard.sh <repo> tick "<marker>"   e.g. "approve-branch=renovate/postgres-18.x",
#                                               "manual job", "rebase-branch=renovate/all-minor-patch"
# Env:   OWNER (default lz-networks)
set -euo pipefail
# Repo → GitHub owner (the fleet spans two owners; a wrong owner reads as "no alerts, no PRs,
# no dashboard" — containerlab-mcp was invisible to the pass all night, 2026-09-09).
owner_of() { case "$1" in containerlab-mcp) echo netpilot-labs;; *) echo "${OWNER:-lz-networks}";; esac; }
R=${1:?repo}; cmd=${2:?show|tick}; marker=${3:-}; OWNER=$(owner_of "$R")
# Server-side `--author app/renovate` returns [] for GitHub *App* bots → "no open dashboard"
# false-negative on every repo whose dashboard IS open (pass-638 fixed this in inventory.sh but
# not here; re-bit pass-688 2026-09-14, blocking a rebase tick). Match title + author in jq instead.
issue=$(gh issue list --repo "$OWNER/$R" --state open --limit 200 --json number,title,author --jq '[.[]|select(.title=="Dependency Dashboard" and .author.login=="app/renovate")][0].number // empty' 2>/dev/null)
[ -z "$issue" ] && { echo "no open Dependency Dashboard in $R (reopen it — gotchas §1)" >&2; exit 2; }
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
gh issue view "$issue" --repo "$OWNER/$R" --json body --jq .body > "$tmp"
case "$cmd" in
  show) echo "dashboard #$issue"; awk '/^## Detected Dependencies/{exit} /^## /{print " " $0} /^ - \[/{print "   " $0}' "$tmp";;
  tick)
    [ -z "$marker" ] && { echo "marker required" >&2; exit 2; }
    if ! grep -qF -- "- [ ] <!-- $marker -->" "$tmp"; then
      echo "marker not found unchecked: $marker" >&2; echo "available:" >&2
      sed -n -E 's/^ - \[ \] <!-- (.*) -->.*/  \1/p' "$tmp" >&2; exit 1
    fi
    perl -pi -e 'BEGIN{$m=shift} s/^(\s*-\s)\[ \](\s*<!--\s*\Q$m\E\s*-->)/$1\[x\]$2/' "$marker" "$tmp"
    gh issue edit "$issue" --repo "$OWNER/$R" --body-file "$tmp" > /dev/null
    echo "ticked on #$issue:"; grep -F -- "<!-- $marker -->" "$tmp";;
  *) echo "cmd must be show|tick" >&2; exit 2;;
esac
