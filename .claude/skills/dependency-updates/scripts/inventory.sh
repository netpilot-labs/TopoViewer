#!/usr/bin/env bash
# inventory.sh — fleet dependency inventory (SKILL.md checklist step 1).
# Prints, per repo: open Dependabot alerts, open Renovate PRs with CI state, and the
# Dependency Dashboard's section headings + unchecked items. Emits `FINDING:` lines for
# stale items. Renovate reads are bounded to 50; reaching that limit emits INCOMPLETE
# and exit 2, so callers must not describe the result as a complete fleet inventory.
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
owner_of() { case "$1" in containerlab-mcp) echo netpilot-labs;; *) echo lz-networks;; esac; }
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
    out=$(printf '%s\n' "$out" | jq -ce 'if type=="array" and length>0 and all(.[]; type=="array") and all(.[][];
        type=="object" and (.number|type)=="number" and .number>0 and .number==(.number|floor)
        and (.security_advisory.severity|type)=="string" and (.dependency.package.name|type)=="string"
        and (.security_vulnerability.vulnerable_version_range|type)=="string"
        and (.security_vulnerability.first_patched_version==null or
          (.security_vulnerability.first_patched_version.identifier|type)=="string")
        and (.dependency.scope==null or (.dependency.scope|type)=="string")
        and (.dependency.manifest_path|type)=="string" and (.created_at|type)=="string") then [.[][]] else error("invalid paginated alerts") end') || {
      echo '  FINDING: alerts unavailable (unreadable paginated response)'; inventory_bad=2; out='[]'; }
  else
    # A 404 can hide missing alert permission; repository readability does not prove absence.
    echo "  FINDING: alerts unavailable (${out%%$'\n'*})"; inventory_bad=2
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
  pr_limit=50
  pr_json=$(gh pr list --repo "$OWNER/$R" --app renovate --state open --limit "$pr_limit" \
    --json number,title,createdAt,isDraft,mergeStateStatus,statusCheckRollup 2>&1) || {
      echo "  FINDING: Renovate PRs unavailable (${pr_json%%$'\n'*})"; inventory_bad=2; pr_json='[]'; }
  pr_count=$(printf '%s\n' "$pr_json" | jq -er 'if type=="array" and all(.[];
      type=="object" and (.number|type)=="number" and .number>0 and .number==(.number|floor)
      and (.title|type)=="string" and (.createdAt|type)=="string" and (.createdAt|length)>0
      and (.mergeStateStatus|type)=="string" and (.mergeStateStatus|length)>0
      and has("statusCheckRollup") and (.statusCheckRollup==null or
        ((.statusCheckRollup|type)=="array" and all(.statusCheckRollup[]; type=="object"))))
      then length else error("invalid PR record fields") end') || {
    echo '  FINDING: Renovate PRs unavailable (unreadable response)'; inventory_bad=2; pr_json='[]'; pr_count=0; }
  if [ "$pr_count" -ge "$pr_limit" ]; then
    echo "  FINDING: Renovate PR inventory INCOMPLETE (limit $pr_limit reached; older open PRs may be omitted)"
    inventory_bad=2
  fi
  prs=$(printf '%s\n' "$pr_json" | jq -er '.[] | [.number, .createdAt, .mergeStateStatus,
          ([.statusCheckRollup[]? | (.conclusion // .state)] | if any(. == "FAILURE") then "RED"
             elif length == 0 then "NO-CI" elif all(. == "SUCCESS" or . == "SKIPPED" or . == "NEUTRAL") then "GREEN" else "PENDING" end),
          .title] | @tsv' 2>&1)
  pr_parse_rc=$?
  # jq -e returns 4 for an empty stream, which is valid only for a proven empty list.
  if [ "$pr_parse_rc" -ne 0 ] && ! { [ "$pr_count" -eq 0 ] && [ "$pr_parse_rc" -eq 4 ]; }; then
    echo "  FINDING: Renovate CI inventory unavailable (${prs%%$'\n'*})"; inventory_bad=2; prs=''
  fi
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
  issues_json=$(gh issue list --repo "$OWNER/$R" --state open --limit 200 --json number,title,author 2>&1) || { echo "  FINDING: dashboard unavailable (${issues_json%%$'\n'*})"; inventory_bad=2; continue; }
  issue_count=$(printf '%s\n' "$issues_json" | jq -er 'if type=="array" and all(.[];
      type=="object" and (.number|type)=="number" and .number>0 and .number==(.number|floor)
      and (.title|type)=="string" and (.author|type)=="object" and (.author.login|type)=="string")
      then length else error("invalid issue response") end') || { echo '  FINDING: dashboard unavailable (unreadable issue response)'; inventory_bad=2; continue; }
  if [ "$issue_count" -ge 200 ]; then
    echo '  FINDING: dashboard discovery INCOMPLETE (issue limit 200 reached; older dashboard may be omitted)'; inventory_bad=2; continue
  fi
  issue=$(printf '%s\n' "$issues_json" | jq -r '[.[]|select(.title=="Dependency Dashboard" and .author.login=="app/renovate")][0].number // empty') || { echo '  FINDING: dashboard unavailable (invalid issue fields)'; inventory_bad=2; continue; }
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
