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
      '"\(.info.name) latest \(.info.version)", ((.info.requires_dist // [])[] | select(ascii_downcase | startswith($p | ascii_downcase)) | "  requires: \(.)")';;
  npm-cap) capper=${1:?}; pkg=${2:?}
    npm view "$capper" version dependencies peerDependencies --json 2>/dev/null | jq -r --arg p "$pkg" \
      '"\($p) latest \(.version)", "  dependencies: \(.dependencies[$p] // "-")", "  peer: \(.peerDependencies[$p] // "-")"';;
  patched) R=${1:?repo}; n=${2:?alert}; OWNER=$(owner_of "$R")
    gh api "repos/$OWNER/$R/dependabot/alerts/$n" --jq '"#\(.number) \(.dependency.package.name) state=\(.state) patched=\(.security_vulnerability.first_patched_version.identifier // "NONE")"';;
  resolvable) pkg=${1:?}
    [ -f uv.lock ] || { echo "run inside a uv repo (no uv.lock here)" >&2; exit 2; }
    # An unrelated stale lock can produce a change plan without moving this package.
    # Require the baseline to be current before interpreting the upgrade dry run.
    check=$(uv lock --check 2>&1); check_rc=$?
    if [ "$check_rc" -ne 0 ]; then
      printf '%s\n' "$check" >&2
      echo "ERROR: current lockfile evidence unavailable for $pkg (uv check exit $check_rc)" >&2
      exit "$check_rc"
    fi
    out=$(uv lock --upgrade-package "$pkg" --dry-run 2>&1); uv_rc=$?
    if [ "$uv_rc" -ne 0 ]; then
      printf '%s\n' "$out" >&2
      echo "ERROR: resolution evidence unavailable for $pkg (uv exit $uv_rc)" >&2
      exit "$uv_rc"
    fi
    printf '%s\n' "$out"
    if grep -q 'No lockfile changes' <<<"$out"; then
      echo "BLOCKED: no lockfile change for $pkg in this dry run — inspect: uv tree --package $pkg --invert (ladder step 3)"
    elif grep -Eq '^Resolved [0-9]+ packages?' <<<"$out"; then
      echo "RESOLVABLE: $pkg dry-run resolution succeeded"
    else
      echo "ERROR: unreadable dry-run resolution evidence for $pkg" >&2
      exit 2
    fi;;
  *) echo "unknown command $cmd" >&2; exit 2;;
esac
