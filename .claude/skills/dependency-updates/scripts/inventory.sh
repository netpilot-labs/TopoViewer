#!/usr/bin/env bash
# inventory.sh — fleet dependency inventory (SKILL.md checklist step 1).
# Prints, per repo: open Dependabot alerts, open Renovate PRs with CI state, and the
# Dependency Dashboard's section headings + unchecked items. Emits `FINDING:` lines for
# stale items so the pass cannot miss them.
#
# Usage: inventory.sh [repo ...]        default = the five fleet repos
# Env:   OWNER (default lz-networks)
#
# Constants (why): a green PR older than PR_STALE_DAYS is unowned work (BE#507 sat 22 d);
# an alert older than ALERT_STALE_DAYS must have a ledger row (BE#29 sat 35 d).
set -uo pipefail
# Repo → GitHub owner (the fleet spans two owners; a wrong owner reads as "no alerts, no PRs,
# no dashboard" — containerlab-mcp was invisible to the pass all night, 2026-09-09).
# NB: fallback is a literal, NOT ${OWNER:-lz-networks} — the loop reassigns the global OWNER each
# iteration, so reading it here leaked containerlab-mcp's netpilot-labs onto the next repo
# (NetPilot-2-LB queried as netpilot-labs/NetPilot-2-LB → 404 alerts + invisible dashboard #6,
# misread as "no dependency graph"; pass-638 2026-09-09).
CONFIGURED_OWNER=${OWNER:-lz-networks}
owner_of() { case "$1" in containerlab-mcp) echo netpilot-labs;; *) echo "$CONFIGURED_OWNER";; esac; }
inventory_bad=0
PR_STALE_DAYS=14
ALERT_STALE_DAYS=30
FLEET="NetPilot-2-Backend NetPilot-2-Frontend netpilot-marketing containerlab-mcp NetPilot-2-LB"

days_since() {  # "2026-09-01T22:28:15Z" -> integer days ago (macOS and GNU date)
  local d=${1%%T*} t0
  t0=$(date -j -f %Y-%m-%d "$d" +%s 2>/dev/null || date -d "$d" +%s 2>/dev/null) || { echo 0; return; }
  echo $(( ( $(date +%s) - t0 ) / 86400 ))
}

repos=${*:-$FLEET}
for R in $repos; do
  echo "== $R"
  OWNER=$(owner_of "$R")
  # --- Dependabot alerts -------------------------------------------------------------
  if out=$(gh api "repos/$OWNER/$R/dependabot/alerts?state=open&per_page=100" --paginate --slurp 2>&1); then
    out=$(printf '%s\n' "$out" | jq -ce 'if type=="array" and all(.[]; type=="array") then [.[][]] else error("invalid paginated alerts") end') || {
      echo '  FINDING: alerts unavailable (unreadable paginated response)'; inventory_bad=2; out='[]'; }
  else
    if [ "$R" = NetPilot-2-LB ] && printf '%s' "$out" | grep -q '"Not Found"'; then
      echo '  alerts: API 404 — Dockerfile-only LB has no dependency graph';
    else echo "  FINDING: alerts unavailable (${out%%$'\n'*})"; inventory_bad=2; fi
    out='[]'
  fi
  echo "$out" | jq -r '.[] | [.number, .security_advisory.severity, .dependency.package.name,
      .security_vulnerability.vulnerable_version_range,
      (.security_vulnerability.first_patched_version.identifier // "NONE"),
      .dependency.scope, .dependency.manifest_path, .created_at] | @tsv' 2>/dev/null |
  while IFS=$'\t' read -r n sev pkg range patched scope manifest created; do
    age=$(days_since "$created")
    printf '  alert #%s %-8s %s %s -> %s [%s] %s %sd\n' "$n" "$sev" "$pkg" "$range" "$patched" "$scope" "$manifest" "$age"
    [ "$patched" = NONE ] && echo "  FINDING: alert #$n $pkg has no patched version — ladder step 4 (ledger row required)"
    [ "$age" -gt "$ALERT_STALE_DAYS" ] && echo "  FINDING: alert #$n $pkg open ${age}d — needs a ledger row with a trigger"
  done
  # --- Renovate PRs ------------------------------------------------------------------
  prs=$(gh pr list --repo "$OWNER/$R" --app renovate --state open --limit 50 \
    --json number,title,createdAt,isDraft,mergeStateStatus,statusCheckRollup \
    --jq '.[] | [.number, .createdAt, .mergeStateStatus,
          ([.statusCheckRollup[]? | (.conclusion // .state)] | if any(. == "FAILURE") then "RED"
             elif length == 0 then "NO-CI" elif all(. == "SUCCESS" or . == "SKIPPED" or . == "NEUTRAL") then "GREEN" else "PENDING" end),
          .title] | @tsv' 2>&1) || { echo "  FINDING: Renovate PRs unavailable (${prs%%$'\n'*})"; inventory_bad=2; prs=''; }
  printf '%s\n' "$prs" |
  while IFS=$'\t' read -r n created state ci title; do
    [ -n "$n" ] || continue
    age=$(days_since "$created")
    printf '  PR #%s %sd %s %s %s\n' "$n" "$age" "$ci" "$state" "$title"
    [ "$ci" = RED ] && echo "  FINDING: PR #$n is RED — diagnose from the lockfile (scripts/lockdiff.sh), never from the PR table"
    [ "$ci" = GREEN ] && [ "$age" -gt "$PR_STALE_DAYS" ] && echo "  FINDING: PR #$n green for ${age}d — unowned; tier it this pass"
    [ "$state" = DIRTY ] && echo "  FINDING: PR #$n has conflicts — tick its rebase-check box (scripts/dashboard.sh)"
  done
  # --- Dependency Dashboard ----------------------------------------------------------
  # no search API (it flaked to "none open" on the LB repo twice, 2026-09-09): list open issues
  # and match title + author in jq. NOT `gh issue list --author app/renovate` — that server-side
  # filter returns [] for GitHub *App* bots (the app-slug form is not accepted), silently reporting
  # "none open" on every repo whose dashboard is open (false-clean, pass-638 2026-09-09). The author
  # login DOES read back as "app/renovate" in the JSON, so filter it there.
  issue=$(gh issue list --repo "$OWNER/$R" --state open --limit 200 --json number,title,author --jq '[.[]|select(.title=="Dependency Dashboard" and .author.login=="app/renovate")][0].number // empty' 2>&1) || { echo "  FINDING: dashboard unavailable (${issue%%$'\n'*})"; inventory_bad=2; continue; }
  if [ -n "$issue" ]; then
    echo "  dashboard: #$issue"
    body=$(gh issue view "$issue" --repo "$OWNER/$R" --json body --jq '.body' 2>&1) || { echo "  FINDING: dashboard body unavailable (${body%%$'\n'*})"; inventory_bad=2; continue; }
    printf '%s\n' "$body" |
      awk '/^## Detected Dependencies/{exit} /^## /{print "   " $0} /^ - \[ \]/{print "    " $0}'
  else
    echo "  dashboard: none open — Renovate not installed here, or the issue was closed (reopen it: gotchas §1)"
  fi
done

exit "$inventory_bad"
