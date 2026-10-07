#!/usr/bin/env bash
# posthog-signal.sh [--window 15m] — mechanics §8 signal for the app after a frontend deploy that
# moved posthog-js: are capture events still arriving? Reads POSTHOG_PERSONAL_API_KEY (a phx_ key
# with read scope) and optional POSTHOG_HOST / POSTHOG_PROJECT_ID from netpilot-devops/.env; the
# frontend's phc_ project token is write-only and cannot answer this (2026-09-10).
# Prints one line. Exit 0 = events seen · 1 = none in the window (REVIEW) · 2 = not configured.
set -uo pipefail
main() {
  local window=15m capture_url="" since="" check_config=0
  while [ $# -gt 0 ]; do case "$1" in
    --window) [ $# -ge 2 ] || return 2; window=$2; shift 2;;
    --capture-url) [ $# -ge 2 ] || return 2; capture_url=$2; shift 2;;
    --since) [ $# -ge 2 ] || return 2; since=$2; shift 2;;
    --check-config) check_config=1; shift;;
    *) echo "posthog: unknown argument"; return 2;;
  esac; done
  local ws; ws=${WORKSPACE:-$(cd "$(dirname "$0")/../../../.." && pwd)}; [ -d "$ws/netpilot-devops" ] || ws=$(cd "$ws/.." && pwd)
  local envf="$ws/netpilot-devops/.env"
  [ -f "$envf" ] && { set -a; . "$envf"; set +a; }
  if [ -z "${POSTHOG_PERSONAL_API_KEY:-}" ]; then echo "posthog: not configured (POSTHOG_PERSONAL_API_KEY missing in netpilot-devops/.env) — signal is page load + Sentry only"; return 2; fi
  local host=${POSTHOG_HOST:-https://us.posthog.com}
  local pid=${POSTHOG_PROJECT_ID:-}
  [ -n "$pid" ] || { echo "posthog: POSTHOG_PROJECT_ID missing in netpilot-devops/.env"; return 2; }
  if [ "$check_config" = 1 ]; then
    python3 - "$host" "$pid" <<'PYPREFLIGHT'
import json,os,sys,urllib.request
try:
 request=urllib.request.Request(sys.argv[1]+'/api/projects/'+sys.argv[2]+'/query/',data=json.dumps({'query':{'kind':'HogQLQuery','query':'select 1'},'refresh':'force_blocking'}).encode(),headers={'Authorization':'Bearer '+os.environ['POSTHOG_PERSONAL_API_KEY'],'Content-Type':'application/json'})
 with urllib.request.urlopen(request,timeout=30) as response: result=json.load(response)
 if result.get('results')!=[[1]] or result.get('is_cached') is not False: raise ValueError('unreadable query')
except (ValueError,KeyError,TypeError,OSError): sys.exit(2)
PYPREFLIGHT
    [ "$?" = 0 ] || { echo "BROKEN: posthog authenticated read-only query prerequisite unavailable"; return 2; }
    echo "posthog: authenticated read-only query prerequisites available"; return 0
  fi
  if [ -n "$capture_url" ] || [ -n "$since" ]; then
    # Independent fresh ingestion proof; never accept ordinary traffic or cached empty answers.
    local n rc
    n=$(python3 - "$host" "$pid" "$capture_url" "$since" <<'PYQUERY'
import datetime,json,os,re,sys,urllib.request
host,pid,url,since=sys.argv[1:]
try:
 if not re.fullmatch(r'https://app[.]netpilot[.]io/sign-in[?]netpilot_deploy_probe=[0-9a-f]{40}[.][0-9a-f]{32}',url) or not re.fullmatch(r'[0-9]{1,12}',since): raise ValueError('arguments')
 boundary=str(int(since))
 query="select count() from events where event = '$pageview' and properties.$current_url = '"+url+"' and timestamp >= toDateTime('"+boundary+"')"
 request=urllib.request.Request(host+'/api/projects/'+pid+'/query/',data=json.dumps({'query':{'kind':'HogQLQuery','query':query},'refresh':'force_blocking'}).encode(),headers={'Authorization':'Bearer '+os.environ['POSTHOG_PERSONAL_API_KEY'],'Content-Type':'application/json','User-Agent':'NetPilot-Deployment-Witness/1.0'})
 with urllib.request.urlopen(request,timeout=30) as response: result=json.load(response)
 if result.get('is_cached') is not False: raise ValueError('freshness unproven')
 n=result['results'][0][0]
 if isinstance(n,bool) or not isinstance(n,int) or n<0: raise ValueError('count')
 print(n)
except (ValueError,KeyError,IndexError,TypeError,OSError): sys.exit(2)
PYQUERY
    ); rc=$?
    [ "$rc" = 0 ] || { echo "BROKEN: posthog exact-nonce query unreadable or freshness unproven"; return 2; }
    if [ "$n" -gt 0 ]; then echo "posthog: $n native exact-nonce pageview(s), independently verified by uncached ingestion query"; return 0; fi
    echo "REVIEW: posthog: no native exact-nonce pageview after the verified deployment boundary"; return 1
  fi
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
