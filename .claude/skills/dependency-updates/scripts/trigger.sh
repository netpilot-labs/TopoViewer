#!/usr/bin/env bash
# trigger.sh — one-command re-checks for the ledger's blocked/dismissed rows (SKILL.md
# step 2; mechanics §7). Each prints the fact the trigger names; the pass compares.
#
# Usage: trigger.sh pypi-cap <capper> <pkg>     latest <capper> + its declared range for <pkg>
#        trigger.sh npm-cap  <capper> <pkg>     same, npm (dependencies + peerDependencies)
#        trigger.sh patched  <repo> <alert-n>   first patched version of the alert, or NONE
#        trigger.sh resolvable <pkg>            can uv move <pkg> under current caps? (run inside a uv repo; dry-run, no write)
# Env:   OWNER (default lz-networks)
set -uo pipefail
# Repo → GitHub owner (the fleet spans two owners; a wrong owner reads as "no alerts, no PRs,
# no dashboard" — containerlab-mcp was invisible to the pass all night, 2026-09-09).
owner_of() { case "$1" in containerlab-mcp) echo netpilot-labs;; *) echo "${OWNER:-lz-networks}";; esac; }
cmd=${1:?}; shift
case "$cmd" in
  pypi-cap) capper=${1:?}; pkg=${2:?}
    curl -sf "https://pypi.org/pypi/$capper/json" | jq -r --arg p "$pkg" \
      '"\(.info.name) latest \(.info.version)", ((.info.requires_dist // [])[] | select((capture("^(?<name>[A-Za-z0-9][A-Za-z0-9._-]*)").name | ascii_downcase | gsub("[-_.]+"; "-")) == ($p | ascii_downcase | gsub("[-_.]+"; "-"))) | "  requires: \(.)")';;
  npm-cap) capper=${1:?}; pkg=${2:?}
    npm view "$capper" version dependencies peerDependencies --json 2>/dev/null | jq -r --arg p "$pkg" \
      '"\($p) latest \(.version)", "  dependencies: \(.dependencies[$p] // "-")", "  peer: \(.peerDependencies[$p] // "-")"';;
  patched) R=${1:?repo}; n=${2:?alert}; OWNER=$(owner_of "$R")
    gh api "repos/$OWNER/$R/dependabot/alerts/$n" --jq '"#\(.number) \(.dependency.package.name) state=\(.state) patched=\(.security_vulnerability.first_patched_version.identifier // "NONE")"';;
  resolvable) pkg=${1:?}
    [ -f uv.lock ] || { echo "run inside a uv repo (no uv.lock here)" >&2; exit 2; }
    out=$(uv lock --upgrade-package "$pkg" --dry-run 2>&1); echo "$out" | tail -n +2
    echo "$out" | grep -q 'No lockfile changes' && echo "BLOCKED: a cap holds $pkg — find it: uv tree --package $pkg --invert (ladder step 3)";;
  *) echo "unknown command $cmd" >&2; exit 2;;
esac
