#!/usr/bin/env bash
# posthog-signal.sh [--window 15m] — mechanics §8 signal for the app after a frontend deploy that
# moved posthog-js: are capture events still arriving? Reads POSTHOG_PERSONAL_API_KEY (a phx_ key
# with read scope) and optional POSTHOG_HOST / POSTHOG_PROJECT_ID from netpilot-devops/.env; the
# frontend's phc_ project token is write-only and cannot answer this (2026-09-10).
# Prints one line. Exit 0 = events seen · 1 = none in the window (REVIEW) · 2 = not configured.
set -uo pipefail
main() {
  local window=15m; [ "${1:-}" = "--window" ] && window=$2
  local ws; ws=${WORKSPACE:-$(cd "$(dirname "$0")/../../../.." && pwd)}; [ -d "$ws/netpilot-devops" ] || ws=$(cd "$ws/.." && pwd)
  local envf="$ws/netpilot-devops/.env"
  [ -f "$envf" ] && { set -a; . "$envf"; set +a; }
  if [ -z "${POSTHOG_PERSONAL_API_KEY:-}" ]; then echo "posthog: not configured (POSTHOG_PERSONAL_API_KEY missing in netpilot-devops/.env) — signal is page load + Sentry only"; return 2; fi
  local host=${POSTHOG_HOST:-https://us.posthog.com}
  local pid=${POSTHOG_PROJECT_ID:-}
  [ -n "$pid" ] || { echo "posthog: POSTHOG_PROJECT_ID missing in netpilot-devops/.env"; return 2; }
  local mins; case "$window" in *m) mins=${window%m};; *h) mins=$(( ${window%h} * 60 ));; *) mins=15;; esac
  # HogQL through the Query API — the only endpoint a `query:read` personal key is scoped for
  local n; n=$(curl -sS -m 30 -H "Authorization: Bearer $POSTHOG_PERSONAL_API_KEY" -H "Content-Type: application/json" \
    -X POST "$host/api/projects/$pid/query/" \
    -d "{\"query\":{\"kind\":\"HogQLQuery\",\"query\":\"select count() from events where timestamp > now() - interval $mins minute\"}}" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["results"][0][0])' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) echo "posthog: query failed (host $host, project $pid)"; return 2;; esac
  if [ "$n" -gt 0 ]; then echo "posthog: $n event(s) captured in the last $window (project $pid) — capture flowing"; return 0; fi
  echo "REVIEW: posthog: 0 events in the last $window (project $pid) — check the deployed page's capture before the next merge"; return 1
}
main "$@"
