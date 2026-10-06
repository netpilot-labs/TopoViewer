#!/usr/bin/env bash
# posthog-signal.sh [--window 15m | --since <unix-seconds>] — mechanics §8 signal for the app after a frontend deploy that
# moved posthog-js: are capture events still arriving? Reads POSTHOG_PERSONAL_API_KEY (a phx_ key
# with read scope) and optional POSTHOG_HOST / POSTHOG_PROJECT_ID from netpilot-devops/.env; the
# frontend's phc_ project token is write-only and cannot answer this (2026-09-10).
# Prints one line. Exit 0 = events seen · 1 = none in the window (REVIEW) · 2 = not configured.
set -uo pipefail
main() {
  local window=15m since="" capture_url="" predicate description
  while [ $# -gt 0 ]; do
    case "$1" in
      --window) [ $# -ge 2 ] || return 2; window=$2; shift 2;;
      --since) [ $# -ge 2 ] || return 2; since=$2; shift 2;;
      --capture-url) [ $# -ge 2 ] || return 2; capture_url=$2; shift 2;;
      *) echo "posthog: unknown argument $1"; return 2;;
    esac
  done
  if [ -n "$since" ]; then
    [[ "$since" =~ ^[0-9]{1,10}$ ]] || { echo "posthog: invalid Unix boundary"; return 2; }
    predicate="timestamp >= toDateTime($since)"; description="since verified deployment boundary $since"
  else
    [[ "$window" =~ ^[0-9]+[mh]$ ]] || { echo "posthog: invalid window"; return 2; }
    local mins; case "$window" in *m) mins=${window%m};; *h) mins=$(( ${window%h} * 60 ));; esac
    predicate="timestamp > now() - interval $mins minute"; description="in the last $window"
  fi
  if [ -n "$capture_url" ]; then
    # A unique URL opened in a fresh browser after the verified version identifies
    # this deployment's real JavaScript pageview; old sessions cannot satisfy it.
    [[ "$capture_url" =~ ^https://app\.netpilot\.io/sign-in\?netpilot_deploy_probe=[0-9a-f]{40}\.[0-9a-f]{32}$ ]] && [ -n "$since" ] || { echo "posthog: invalid deployment capture URL/boundary"; return 2; }
    predicate="$predicate and event = '\$pageview' and properties.\$current_url = '$capture_url'"
    description="for deployment browser probe $capture_url since $since"
  fi
  local ws; ws=${WORKSPACE:-$(cd "$(dirname "$0")/../../../.." && pwd)}; [ -d "$ws/netpilot-devops" ] || ws=$(cd "$ws/.." && pwd)
  local envf="$ws/netpilot-devops/.env"
  [ -f "$envf" ] && { set -a; . "$envf"; set +a; }
  if [ -z "${POSTHOG_PERSONAL_API_KEY:-}" ]; then echo "posthog: not configured (POSTHOG_PERSONAL_API_KEY missing in netpilot-devops/.env) — signal is page load + Sentry only"; return 2; fi
  local host=${POSTHOG_HOST:-https://us.posthog.com}
  local pid=${POSTHOG_PROJECT_ID:-}
  [ -n "$pid" ] || { echo "posthog: POSTHOG_PROJECT_ID missing in netpilot-devops/.env"; return 2; }
  # HogQL through the Query API — the only endpoint a `query:read` personal key is scoped for
  local payload; payload=$(python3 -c 'import json,sys; print(json.dumps({"query":{"kind":"HogQLQuery","query":"select count() from events where " + sys.argv[1]}}))' "$predicate") || return 2
  local n; n=$(curl -fsS -m 30 -H "Authorization: Bearer $POSTHOG_PERSONAL_API_KEY" -H "Content-Type: application/json" \
    -X POST "$host/api/projects/$pid/query/" \
    -d "$payload" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["results"][0][0])' 2>/dev/null) || { echo "posthog: query failed (host $host, project $pid)"; return 2; }
  case "$n" in ''|*[!0-9]*) echo "posthog: query failed (host $host, project $pid)"; return 2;; esac
  if [ "$n" -gt 0 ]; then echo "posthog: $n event(s) captured $description (project $pid) — capture flowing"; return 0; fi
  echo "REVIEW: posthog: 0 events $description (project $pid) — check the deployed page's capture before the next merge"; return 1
}
main "$@"
