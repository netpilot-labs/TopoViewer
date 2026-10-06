#!/usr/bin/env bash
# alert.sh — Dependabot alert state changes (mechanics §7). Reversible; touches nothing in
# prod. Dismissal never reopens by itself — the ledger row is the path back.
#
# Usage: alert.sh <repo> show <n>
#        alert.sh <repo> dismiss <n> <reason> "<comment>"   reason: fix_started|inaccurate|not_used|tolerable_risk
#        alert.sh <repo> reopen <n>
# Env:   OWNER (default lz-networks)
# The comment cap (280 chars) is GitHub's; `no_bandwidth` is refused — it is the state this
# skill exists to remove. A runtime-reachable `tolerable_risk` is Lin's call (tiers §6.4).
set -euo pipefail
# Repo → GitHub owner (the fleet spans two owners; a wrong owner reads as "no alerts, no PRs,
# no dashboard" — containerlab-mcp was invisible to the pass all night, 2026-09-09).
owner_of() { case "$1" in containerlab-mcp) echo netpilot-labs;; *) echo "${OWNER:-lz-networks}";; esac; }
R=${1:?repo}; cmd=${2:?show|dismiss|reopen}; n=${3:?alert number}; OWNER=$(owner_of "$R")
api="repos/$OWNER/$R/dependabot/alerts/$n"
show() { gh api "$api" --jq '"#\(.number) \(.state) \(.security_advisory.severity) \(.dependency.package.name) \(.security_vulnerability.vulnerable_version_range) -> \(.security_vulnerability.first_patched_version.identifier // "NONE") [\(.dependency.scope)] \(.security_advisory.ghsa_id) \(.security_advisory.cve_id // "")" + (if .dismissed_reason then " dismissed=\(.dismissed_reason): \(.dismissed_comment // "")" else "" end)'; }
case "$cmd" in
  show) show;;
  dismiss)
    reason=${4:?reason}; comment=${5:?comment}
    case "$reason" in fix_started|inaccurate|not_used|tolerable_risk) ;;
      no_bandwidth) echo "refused: no_bandwidth is never this skill's reason" >&2; exit 1;;
      *) echo "reason must be fix_started|inaccurate|not_used|tolerable_risk" >&2; exit 2;; esac
    [ ${#comment} -gt 280 ] && { echo "comment is ${#comment} chars; GitHub caps it at 280" >&2; exit 2; }
    gh api -X PATCH "$api" -f state=dismissed -f dismissed_reason="$reason" -f dismissed_comment="$comment" > /dev/null
    show;;
  reopen) gh api -X PATCH "$api" -f state=open > /dev/null; show;;
  *) echo "cmd must be show|dismiss|reopen" >&2; exit 2;;
esac
