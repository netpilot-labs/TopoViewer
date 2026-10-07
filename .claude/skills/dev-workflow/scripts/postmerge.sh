#!/usr/bin/env bash
# postmerge.sh — the post-merge deploy watch of dev-workflow/deploy.md, executed (SKILL.md step 10;
# the per-repo signal table is dependency-updates/mechanics.md §8). Run it
# after `gh pr merge`, before the next merge in that repo. Deterministic signals decide the
# exit code; Sentry new groups are printed for the pass to attribute (judgment).
#
# Usage: postmerge.sh <repo> <merge-sha> [--sentry-window 1h] [--skip-sentry]
#   NetPilot-2-Backend / NetPilot-2-LB   Railway deployment for the sha reaches SUCCESS, then
#                                        /health sampled; Backend also waits for the `main` push
#                                        run (the only place the real-Clerk job executes).
#   NetPilot-2-Frontend / netpilot-marketing   Vercel deployment for the sha reaches `success`,
#                                        then a route load (app: /sign-in 200 + version.json
#                                        stamps the sha; marketing: / 200).
#   No-deploy repositories   retain the merge slot until the actual default-branch push CI for
#                            the exact merge SHA has succeeded, including required named jobs.
#                            Wait up to 25 minutes; missing/unreadable evidence is BROKEN.
#                            Repositories with no workflows settle clean without a CI wait.
# Exit: 0 clean · 1 RED · 2 broken/timeout (trust nothing; look by hand)
#       3 REVIEW — every deterministic signal passed but a REVIEW line (new Sentry groups, 0 PostHog
#       events) needs attributing before the next merge in that repo; never read as clean
#       RED is not "revert" (Lin, 2026-10-01): the RESULT line names which signal fired — production
#       answering non-200 (health / route load, sampled) = ROLL BACK first; a failed deploy with production still
#       answering = judge the impact; the main run alone = read the failed job first — the real-Clerk job
#       failing on sign-in is a core flow (roll back), a test fault is fix forward (deploy.md; BE PR#942).
# Env:  OWNER (lz-networks), WORKSPACE (auto), MERGE_CLAIM_DIR (the merge slot; settled here on exit — merge-slot.sh)
#
# Constants (why): DEPLOY_TIMEOUT_MIN=20 covers a Railway build+rollout (~8–12 min) and a
# Vercel build (~3–6); VERCEL_APPEAR_MIN=3 — a merge with no deployment record after ~3 min
# is an event miss, not a slow build (dev-workflow/deploy.md); HEALTH_SAMPLES=5 needing ≥4 OK —
# one 503 at cutover is the drain-aware replica, never a failure (dev-workflow/deploy.md); the route load is sampled the same way;
# PARSE_TOLERANCE=3 — the Railway CLI returned one unparseable response mid-watch on the
# first live run (BE PR#738, 2026-09-09) while the next poll parsed fine; only a streak
# means auth/outage.
# The whole body runs inside main() so an edit to this file while an instance is running
# cannot change that instance mid-flight (bash reads scripts lazily; 2026-09-09: an edit
# killed a live ci-wait with a syntax error at the line being rewritten).
main() {
set -uo pipefail
# Repo → GitHub owner (the fleet spans two owners; a wrong owner reads as "no alerts, no PRs,
# no dashboard" — containerlab-mcp was invisible to the pass all night, 2026-09-09).
owner_of() { case "$1" in containerlab-mcp|TopoViewer) echo netpilot-labs;; *) echo "${OWNER:-lz-networks}";; esac; }
DEPLOY_TIMEOUT_MIN=20; VERCEL_APPEAR_MIN=3; HEALTH_SAMPLES=5; HEALTH_MIN_OK=4; PARSE_TOLERANCE=3
R=${1:?repo}; sha=${2:?merge sha (full 40-char)}; shift 2
[ "$R" = topoViewer ] && R=TopoViewer
OWNER=$(owner_of "$R")
window=1h; skip_sentry=0
while [ $# -gt 0 ]; do case "$1" in --sentry-window) window=$2; shift 2;; --skip-sentry) skip_sentry=1; shift;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
[[ "$sha" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "merge sha must be the full 40-char oid (gotchas: never hand-type one)" >&2; exit 2; }
# GitHub returns canonical lowercase object IDs; accepted hexadecimal input has
# one identity for run filtering and merge-slot settlement.
sha=$(printf '%s' "$sha" | tr '[:upper:]' '[:lower:]')
folder=$R; [ "$R" = TopoViewer ] && folder=topoViewer
ws=${WORKSPACE:-$(cd "$(dirname "$0")/../../../.." && pwd)}; [ -d "$ws/$folder/.git" ] || ws=$(cd "$ws/.." && pwd)
red=0; broken=0; review=0; ci_only=""; outage=0
say() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }
SLOT="$(cd "$(dirname "$0")" && pwd)/merge-slot.sh"
no_deploy=0
case "$R" in
  NetPilot-2-Backend|NetPilot-2-LB|NetPilot-2-Frontend|netpilot-marketing|containerlab-mcp|netpilot-skills|netpilot-probe-lab|netpilot-devops|netpilot-dev|netpilot-lead-desk|netpilot-support-desk|netpilot-marketing-monitor|3rd-party-apps|TopoViewer) ;;
  *) echo "unknown repo $R — refusing to create a merge hold" >&2; exit 2;;
esac
# merge-slot.sh settle on EVERY exit: clean frees the repo's merge slot; RED/BROKEN/REVIEW (an interrupted watch is
# BROKEN) is written into it and it stays held until read (skills PR#55). SLOT's path was resolved before any cd.
slot_result() { case $1 in 0) [ $skip_sentry = 1 ] && [ $no_deploy = 0 ] && echo clean-skip || echo clean;; 3) echo REVIEW;; 1) [ $review = 1 ] && echo RED+REVIEW || echo RED;; *) [ $review = 1 ] && echo BROKEN+REVIEW || echo BROKEN;; esac; }
trap 'rc=$?; [ -x "$SLOT" ] && "$SLOT" settle "$OWNER/$R" "$sha" "$(slot_result $rc)"' EXIT
trap 'exit 2' INT TERM

# Known no-deploy repositories hold the same merge slot through bounded default-branch CI.
# Arm settlement before inventory reads so API failure records BROKEN, including on a fresh
# merge. Unknown names were rejected above and cannot create holds. Required push evidence
# must be complete, successful and old enough for all workflow runs to have been minted.
case "$R" in
  NetPilot-2-Backend|NetPilot-2-LB|NetPilot-2-Frontend|netpilot-marketing) ;;
  containerlab-mcp|netpilot-skills|netpilot-probe-lab|netpilot-devops|netpilot-dev|netpilot-lead-desk|netpilot-support-desk|netpilot-marketing-monitor|3rd-party-apps|TopoViewer)
    no_deploy=1
    wf=$(gh api "repos/$OWNER/$R/actions/workflows" --jq .total_count) || wf="UNREADABLE"
    expected_push=""
    case "$R" in
      containerlab-mcp) expected_push=.github/workflows/test.yml;;
      TopoViewer) expected_push=.github/workflows/ci.yml;;
      netpilot-probe-lab) expected_push=.github/workflows/probe-lab-checks.yml;;
    esac
    if [ "$wf" = 0 ] && [ -z "$expected_push" ]; then
      say "RESULT: no deploy on merge for $R — no workflows; no default-branch CI to wait for"
      exit 0
    fi
    if ! [[ "$wf" =~ ^[0-9]+$ ]] || [ "$wf" = 0 ] || [ -z "$expected_push" ]; then
      say "RESULT: BROKEN — unreadable or unsupported required default-branch push workflow inventory for $R; any existing hold stays"
      exit 2
    fi
    default=$(gh api "repos/$OWNER/$R" --jq .default_branch) || default=""
    [ -n "$default" ] && [ "$default" != null ] || { say "RESULT: BROKEN — cannot read default branch for $R"; exit 2; }
    deadline=$(( $(date +%s) + 25*60 )); RUNS_APPEAR_S=180
    while :; do
      # Scope immutable merge SHA, event and actual default branch before choosing latest runs.
      raw=$(gh api "repos/$OWNER/$R/actions/runs?head_sha=$sha&event=push&per_page=100" --paginate --slurp) || { say "RESULT: BROKEN — cannot read default-branch push runs"; exit 2; }
      runs=$(printf '%s' "$raw" | jq -c --arg head "$sha" --arg branch "$default" '
        [.[].workflow_runs[] | select(.head_sha==$head and .head_branch==$branch and .event=="push")
          | .path=(.path|split("@")[0])] | group_by(.path) | map(sort_by(.created_at,.id)|last)') || { say "RESULT: BROKEN — unreadable push run inventory"; exit 2; }
      present=$(printf '%s' "$runs" | jq -r --arg path "$expected_push" 'any(.[]; .path==$path)')
      pending=0
      if [ "$present" != true ]; then pending=1; fi
      while IFS=$'\t' read -r id path status conclusion; do
        [ -n "$id" ] || continue
        if [ "$status" != completed ]; then pending=1; continue; fi
        case "$conclusion" in
          success) ;;
          failure|cancelled|timed_out|action_required|startup_failure) say "RESULT: RED — default-branch push workflow $path ended $conclusion for ${sha:0:8}"; exit 1;;
          *) say "RESULT: BROKEN — default-branch push workflow $path did not prove success ($conclusion)"; exit 2;;
        esac
        python3 "$(dirname "$0")/ci-jobs.py" "$OWNER/$R" "$id" "$path" "$sha"; job_rc=$?
        case "$job_rc" in
          0) ;;
          1) say "RESULT: RED — required default-branch jobs did not succeed for $path"; exit 1;;
          *) say "RESULT: BROKEN — required default-branch jobs unreadable for $path"; exit 2;;
        esac
      done < <(printf '%s' "$runs" | jq -r '.[]|[.id,.path,.status,(.conclusion // "-")]|@tsv')
      age=$(gh api "repos/$OWNER/$R/commits/$sha" --jq .commit.committer.date | python3 -c 'import sys,datetime,time; print(int(time.time()-datetime.datetime.fromisoformat(sys.stdin.read().strip().replace("Z","+00:00")).timestamp()))' 2>/dev/null) || { say "RESULT: BROKEN — merge commit age unreadable"; exit 2; }
      if [ "$pending" = 0 ] && [[ "$age" =~ ^[0-9]+$ ]] && [ "$age" -ge $RUNS_APPEAR_S ]; then
        say "RESULT: no deploy on merge for $R — required default-branch push workflows/jobs verified for ${sha:0:8}"
        exit 0
      fi
      [ "$(date +%s)" -ge "$deadline" ] && { say "RESULT: BROKEN — required default-branch push CI missing or pending after 25 minutes for ${sha:0:8}; any existing hold stays"; exit 2; }
      say "default-branch push CI for ${sha:0:8} missing/pending — waiting"
      sleep 20
    done;;
  *) echo "unknown repo $R — deploy repos: NetPilot-2-Backend NetPilot-2-LB NetPilot-2-Frontend netpilot-marketing; no deploy on merge: containerlab-mcp netpilot-skills netpilot-probe-lab netpilot-devops netpilot-dev netpilot-lead-desk netpilot-support-desk netpilot-marketing-monitor 3rd-party-apps topoViewer" >&2; exit 2;;
esac

probe_samples() {  # url [curl timeout] -> HEALTH_SAMPLES samples. Only an HTTP answer other than 200 counts toward an
  # outage; a sample with NO answer (curl rc!=0 / 000: DNS, connect, timeout on THIS machine) never does (Codex, skills PR#54)
  local url=$1 t=${2:-10} ok=0 bad=0 unread=0 i code rc
  for i in $(seq 1 $HEALTH_SAMPLES); do
    code=$(curl -s -o /dev/null -m "$t" -w '%{http_code}' "$url"); rc=$?
    if [ $rc -ne 0 ] || [ "$code" = 000 ]; then unread=$((unread+1)); code="rc$rc"; elif [ "$code" = 200 ]; then ok=$((ok+1)); else bad=$((bad+1)); fi
    printf '%s ' "$code"; sleep 3
  done; echo
  if [ $ok -ge $HEALTH_MIN_OK ]; then say "probe $url ok=$ok/$HEALTH_SAMPLES"
  elif [ $bad -gt $((HEALTH_SAMPLES-HEALTH_MIN_OK)) ]; then say "RED: $url answered non-200 ${bad}× of $HEALTH_SAMPLES (ok=$ok)"; red=1; outage=1
  else say "BROKEN: $url gave no HTTP answer ${unread}× of $HEALTH_SAMPLES (DNS, connect or timeout from this machine) — not an outage reading; probe it from another network, and roll back if users cannot reach it"; broken=1; fi
}

railway_health() {
  probe_samples https://api.netpilot.io/health
  if [ $red = 0 ] && [ $broken = 0 ]; then
    say "railway health: initial samples passed; checking again after five minutes"
    sleep 300
    probe_samples https://api.netpilot.io/health
  fi
}

railway_identity() {  # current serving identity at acceptance and final settlement
  local live="" raw
  case "$R" in
    NetPilot-2-Backend|NetPilot-2-LB)
      raw=$(railway deployment list --service "$R" --limit 100 --json 2>/dev/null) || { say "BROKEN: latest served Railway deployment unreadable"; broken=1; return; }
      live=$(printf '%s' "$raw" | python3 -c '
import datetime,json,re,sys
try:
 rows=json.loads(sys.stdin.read(),strict=False)
 if not isinstance(rows,list): raise ValueError("deployment list")
 active=[x for x in rows if x.get("status")=="SUCCESS"]
 if not active: raise ValueError("no successful deployment")
 def key(x): return datetime.datetime.fromisoformat(x["createdAt"].replace("Z","+00:00"))
 current=max(active,key=key); sha=(current.get("meta") or {}).get("commitHash","")
 if not re.fullmatch("[0-9a-fA-F]{40}",sha): raise ValueError("deployment SHA")
 print(sha)
except (ValueError,TypeError,KeyError,AttributeError): sys.exit(2)') || { say "BROKEN: latest served Railway deployment identity unreadable"; broken=1; return; };;
  esac
  if [ "$live" != "$sha" ]; then
    say "REVIEW: live deployment $live differs from watched $sha — attribute both diffs and restart the observation from the newer deployment; do not release the merge slot"
    review=1
  else say "current served deployment identity verified for ${sha:0:8}"; fi
}

railway_wait() {  # service -> waits for the sha's deployment
  local svc=$1 deadline=$(( $(date +%s) + DEPLOY_TIMEOUT_MIN*60 )) st bad=0
  cd "$ws/$R" || { broken=1; return; }
  while :; do
    st=$(railway deployment list --service "$svc" --json 2>/dev/null | python3 -c '
import json,sys
sha=sys.argv[1]
try: d=json.loads(sys.stdin.read(),strict=False)
except Exception: print("PARSE"); sys.exit()
for x in d:
    if (x.get("meta") or {}).get("commitHash","").startswith(sha): print(x.get("status","?")); sys.exit()
print("NONE")' "$sha") || st=PARSE
    [ "$st" != PARSE ] && bad=0
    case "$st" in
      SUCCESS) say "railway $svc: SUCCESS for ${sha:0:8}"; railway_identity; return;;
      FAILED|CRASHED) say "RED: railway $svc deployment $st for ${sha:0:8}"; red=1; return;;
      NEEDS_APPROVAL) say "BROKEN: railway deployment NEEDS_APPROVAL (dev-workflow/deploy.md has the GraphQL approve)"; broken=1; return;;
      PARSE) bad=$((bad+1)); if [ $bad -ge $PARSE_TOLERANCE ]; then say "BROKEN: railway CLI output unparseable ${bad}× in a row — unauthenticated or CLI outage; run it in the foreground (dev-workflow/deploy.md)"; broken=1; return; fi; say "railway $svc: transient unparseable response ($bad/$PARSE_TOLERANCE) …"; sleep 20;;
      *) [ $(date +%s) -gt $deadline ] && { say "BROKEN: railway $svc still $st after ${DEPLOY_TIMEOUT_MIN} min"; broken=1; return; }; say "railway $svc: $st …"; sleep 30;;
    esac
  done
}

main_run_wait() {  # backend: the push run on main for this sha
  local deadline=$(( $(date +%s) + 25*60 )) id st default raw
  default=$(gh api "repos/$OWNER/$R" --jq .default_branch) || { say "BROKEN: cannot read backend default branch"; broken=1; return; }
  [ -n "$default" ] && [ "$default" != null ] || { say "BROKEN: backend default branch unreadable"; broken=1; return; }
  while :; do
    raw=$(gh api "repos/$OWNER/$R/actions/runs?head_sha=$sha&event=push&per_page=100" --paginate --slurp) || { say "BROKEN: cannot read backend push runs"; broken=1; return; }
    id=$(printf '%s' "$raw" | jq -r --arg head "$sha" --arg branch "$default" '[.[].workflow_runs[] | select(.head_sha==$head and .head_branch==$branch and .event=="push" and (.path|split("@")[0])==".github/workflows/agents_service.yml")] | sort_by(.created_at,.id) | last | .id // empty') || { say "BROKEN: backend push run inventory unreadable"; broken=1; return; }
    [ -n "$id" ] && break; [ $(date +%s) -gt $deadline ] && { say "BROKEN: no push run on main for ${sha:0:8}"; broken=1; return; }; sleep 20
  done
  while :; do
    st=$(gh run view "$id" -R "$OWNER/$R" --json status,conclusion --jq '"\(.status)/\(.conclusion)"') || { say "BROKEN: cannot read main run $id conclusion"; broken=1; return; }
    case "$st" in completed/*) break;; esac
    [ $(date +%s) -gt $deadline ] && { say "BROKEN: main run $id still $st"; broken=1; return; }; sleep 30
  done
  case "$st" in
    completed/success) ;;
    completed/failure|completed/cancelled|completed/timed_out)
      say "RED: main run $id ended $st"; [ $red = 0 ] && ci_only=$id; red=1; return;;
    *) say "BROKEN: main run $id ended $st — success was not verified"; broken=1; return;;
  esac
  local jobs badjobs authjob
  jobs=$(gh run view "$id" -R "$OWNER/$R" --json jobs --jq '.jobs[]|"  job \(.name): \(.conclusion)"') || { say "BROKEN: cannot read main run $id jobs"; broken=1; return; }
  printf '%s\n' "$jobs"
  badjobs=$(gh run view "$id" -R "$OWNER/$R" --json jobs --jq '[.jobs[]|select(.conclusion!="success" and .conclusion!="skipped")]|length') || { say "BROKEN: cannot verify main run $id job conclusions"; broken=1; return; }
  [[ "$badjobs" =~ ^[0-9]+$ ]] || { say "BROKEN: invalid main run $id job conclusions"; broken=1; return; }
  if [ "$badjobs" -ne 0 ]; then
    say "RED: main run $id has a failed job — the real-Clerk job runs only here (mechanics §8)"; [ $red = 0 ] && ci_only=$id; red=1
  else
    authjob=$(gh run view "$id" -R "$OWNER/$R" --json jobs --jq '[.jobs[]|select(.name=="API Integration Tests (Real Clerk Auth)")]|if length==1 then .[0].conclusion else "missing-or-duplicate" end') || { say "BROKEN: cannot verify main run $id real-Clerk job"; broken=1; return; }
    if [ "$authjob" != success ]; then
      say "RED: main run $id real-Clerk job was not successful ($authjob)"; [ $red = 0 ] && ci_only=$id; red=1
    else say "main run $id: all jobs green/skipped; real-Clerk job success verified"; fi
  fi
}

production_identity() {  # called at signal acceptance and once more before clean settlement
  local live="" raw ids id candidate status
  case "$R" in
    NetPilot-2-Frontend)
      live=$(curl -fsS -m 15 -H "Cache-Control: no-cache" https://app.netpilot.io/version.json 2>/dev/null | python3 -c '
import json,re,sys
try:
 sha=json.load(sys.stdin).get("version","")
 if not isinstance(sha,str) or not re.fullmatch("[0-9a-fA-F]{40}",sha): raise ValueError("version")
 print(sha)
except (ValueError,TypeError,AttributeError): sys.exit(2)') || { say "BROKEN: current served frontend version unreadable at settlement"; broken=1; return; };;
    netpilot-marketing)
      ids=$(gh api "repos/$OWNER/$R/deployments?environment=production&per_page=100" --paginate --slurp | python3 -c '
import datetime,json,re,sys
try:
 pages=json.load(sys.stdin)
 if not isinstance(pages,list) or any(not isinstance(p,list) for p in pages): raise ValueError("deployment pages")
 rows=[x for page in pages for x in page if x.get("environment","").lower()=="production"]
 def key(x):
  when=datetime.datetime.fromisoformat(x["created_at"].replace("Z","+00:00"))
  if when.tzinfo is None or not isinstance(x["id"],int) or x["id"]<=0 or not re.fullmatch("[0-9a-fA-F]{40}",x["sha"]): raise ValueError("deployment identity")
  return when,x["id"]
 for x in sorted(rows,key=key,reverse=True): print(str(x["id"])+"\t"+x["sha"])
except (ValueError,TypeError,KeyError,AttributeError): sys.exit(2)') || { say "BROKEN: latest Production deployment inventory unreadable"; broken=1; return; }
      while IFS=$'\t' read -r id candidate; do
        [ -n "$id" ] || continue
        [[ "$id" =~ ^[0-9]+$ ]] && [[ "$candidate" =~ ^[0-9a-fA-F]{40}$ ]] || { say "BROKEN: latest Production deployment identity unreadable"; broken=1; return; }
        status=$(gh api "repos/$OWNER/$R/deployments/$id/statuses" --jq '.[0].state // "unreadable"') || { say "BROKEN: latest Production deployment status unreadable"; broken=1; return; }
        case "$status" in
          success) live=$candidate; break;;
          pending|queued|in_progress|failure|error|inactive) ;; # these records do not prove a newly serving deployment
          *) say "BROKEN: latest Production deployment status unreadable ($status)"; broken=1; return;;
        esac
      done <<< "$ids"
      [ -n "$live" ] || { say "BROKEN: no successful Production deployment identity"; broken=1; return; };;
  esac
  if [ "$live" != "$sha" ]; then
    say "REVIEW: live deployment $live differs from watched $sha — attribute both diffs and restart the observation from the newer deployment; do not release the merge slot"
    review=1
  else say "current served deployment identity verified for ${sha:0:8}"; fi
}

vercel_wait() {  # route url [version-url]
  local deadline=$(( $(date +%s) + DEPLOY_TIMEOUT_MIN*60 )) appear=$(( $(date +%s) + VERCEL_APPEAR_MIN*60 )) id st
  while :; do
    id=$(gh api "repos/$OWNER/$R/deployments?sha=$sha&environment=production" --jq '.[0].id // empty') || { say "BROKEN: Production target deployment inventory unreadable"; broken=1; return; }
    [ -n "$id" ] && break
    [ $(date +%s) -gt $appear ] && { say "BROKEN: no Vercel deployment for ${sha:0:8} after ${VERCEL_APPEAR_MIN} min — event miss; push an empty lz-networks-authored commit (dev-workflow/deploy.md)"; broken=1; return; }
    sleep 15
  done
  while :; do
    st=$(gh api "repos/$OWNER/$R/deployments/$id/statuses" --jq '.[0].state // "pending"') || { say "BROKEN: Production target deployment status unreadable"; broken=1; return; }
    case "$st" in
      success) say "vercel deployment $id: success"; if [ "$R" = netpilot-marketing ]; then production_identity; fi; break;;
      failure|error) say "RED: vercel deployment $id: $st (the fix is NOT live)"; red=1; probe_samples "$1" 15; return;;
      *) [ $(date +%s) -gt $deadline ] && { say "BROKEN: vercel deployment $id still $st"; broken=1; return; }; sleep 20;;
    esac
  done
  probe_samples "$1" 15  # also run after a FAILED deploy above, so the RESULT line never guesses
  [ $red = 0 ] && [ $outage = 0 ] || return  # report confirmed impact before version/capture waits
  if [ -n "${2:-}" ]; then
    # The CDN can still answer with the previous deployment's stamp for a few seconds after the
    # deployment reports success (FE#499: previous sha at +1 s, new sha at +2 s, 2026-09-11) —
    # and it ignores query strings on static files, so retry rather than cache-bust.
    local v="" i
    for i in 1 2 3 4 5 6; do
      v=$(curl -fsS -m 15 -H "Cache-Control: no-cache" "$2" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>/dev/null) || v=""
      [ "$v" = "$sha" ] && break; sleep 10
    done
    if [ "$v" = "$sha" ]; then ph_since=$(date +%s); say "version stamp $v"
    else say "BROKEN: version.json did not prove ${sha:0:8} live after six reads (last stamp: ${v:-unreadable}) — verify the deployment before releasing the merge slot"; broken=1; fi
  fi
}

sentry_new() {  # project slug
  [ $skip_sentry = 1 ] && return
  local envf="$ws/netpilot-devops/.env" sh="$ws/netpilot-devops/scripts/sentry.sh"
  [ -f "$envf" ] && [ -x "$sh" ] || { say "BROKEN: sentry helper or .env missing — no signal read; check the Sentry MCP by hand"; broken=1; return; }
  local out rc; out=$(set -a; . "$envf"; set +a; "$sh" list "$1" "is:unresolved firstSeen:-$window" 2>/dev/null); rc=$?
  # a failed query (expired token, API outage) must not read as "no new groups" (Codex, netpilot-skills PR#45)
  [ $rc -ne 0 ] && { say "BROKEN: sentry $1 query failed (rc=$rc) — no signal read; look by hand"; broken=1; return; }
  if [ -n "$out" ]; then say "REVIEW: Sentry $1 groups first seen in the last $window (attribute before the next merge):"; printf '%s\n' "$out" | sed 's/^/    /'; review=1; else say "sentry $1: no new unresolved groups in $window"; fi
}

case "$R" in
  NetPilot-2-Backend)
    # health is sampled after a FAILED/CRASHED deploy too: it decides roll back vs fix forward (Codex, skills PR#54)
    # REVIEW is an attribution hold; it never replaces deterministic main-CI proof.
    railway_wait NetPilot-2-Backend; dep_red=$red; railway_health; [ $dep_red = 0 ] && [ $red = 0 ] && [ $broken = 0 ] && main_run_wait
    [ $outage = 0 ] && sentry_new netpilot-backend;;
  NetPilot-2-LB)
    railway_wait NetPilot-2-LB; railway_health;;
  NetPilot-2-Frontend)
    vercel_wait https://app.netpilot.io/sign-in https://app.netpilot.io/version.json; [ $outage = 0 ] && sentry_new netpilot-frontend
    # Strict frontend acceptance: real authenticated native pageview plus independent fresh ingestion.
    phs="$(dirname "$0")/../../dependency-updates/scripts/posthog-signal.sh"
    browser="$(dirname "$0")/browser-capture-probe.py"
    if [ "$outage" = 0 ] && [ "$red" = 0 ] && [ "$broken" = 0 ]; then
      if [ ! -x "$phs" ] || [ ! -f "$browser" ]; then
        say "BROKEN: required frontend capture verifier missing"; broken=1
      else
        pout=$(WORKSPACE="$ws" python3 "$browser" --check-config); prc=$?; say "$pout"
        [ "$prc" = 0 ] && { pout=$(WORKSPACE="$ws" "$phs" --check-config); prc=$?; say "$pout"; }
        if [ "$prc" != 0 ]; then say "BROKEN: frontend authenticated capture prerequisites unavailable"; broken=1
        else
          ph_since=$(date +%s)
          ph_nonce=$(python3 -c 'import secrets; print(secrets.token_hex(16))') || { say "BROKEN: cannot create capture nonce"; exit 2; }
          ph_url="https://app.netpilot.io/sign-in?netpilot_deploy_probe=$sha.$ph_nonce"
          pout=$(WORKSPACE="$ws" python3 "$browser" "$ph_url" "$sha"); prc=$?; say "$pout"
          if [ "$prc" != 0 ]; then say "BROKEN: authenticated native capture failed or owned-session revoke failed"; broken=1
          else
            for ph_attempt in $(seq 1 30); do
              pout=$(WORKSPACE="$ws" "$phs" --since "$ph_since" --capture-url "$ph_url"); prc=$?
              case "$prc" in
                0) say "$pout"; break;;
                1) [ "$ph_attempt" = 30 ] && { say "$pout"; review=1; break; }; sleep 30;;
                *) say "$pout"; say "BROKEN: exact-nonce ingestion verification unavailable"; broken=1; break;;
              esac
            done
          fi
        fi
      fi
    fi;;
  netpilot-marketing)
    vercel_wait https://www.netpilot.io/;;
esac
# Every otherwise successful path remeasures final identity, including REVIEW holds.
case "$R" in NetPilot-2-Backend|NetPilot-2-LB) [ $red = 0 ] && [ $broken = 0 ] && railway_identity;; esac
case "$R" in NetPilot-2-Frontend|netpilot-marketing) [ $red = 0 ] && [ $broken = 0 ] && production_identity;; esac
[ $outage = 1 ] && { say "RESULT: RED — production answers non-200 (health / route samples above): ROLL BACK first (dependency-updates/scripts/revert-pr.sh, or git revert + self-merge; the platform rollback buys the minutes — deploy.md), then report"; exit 1; }
# A failure next to an unread or unattributed impact signal is never called "no user impact" (Codex, skills PR#54)
[ $red = 1 ] && [ $broken = 1 ] && { say "RESULT: RED — a deploy or main-run failure above AND a signal that could not be read (BROKEN line above): the impact is UNKNOWN — look by hand now; an outage or many users hit = roll back, else fix forward (deploy.md)"; exit 1; }
[ $red = 1 ] && [ $review = 1 ] && { say "RESULT: RED — a deploy or main-run failure above AND a REVIEW line (new Sentry groups / 0 PostHog events): attribute it first — count the users and events on each group; many users hit = roll back, else fix forward (deploy.md)"; exit 1; }
sn=", no new Sentry groups"; [ $skip_sentry = 1 ] && sn=", Sentry SKIPPED — read it by hand"
[ -n "$ci_only" ] && { say "RESULT: RED — main run $ci_only only (deploy SUCCESS, health ok$sn): read the failed job FIRST (gh run view $ci_only -R $OWNER/$R --log-failed) — a job showing a core flow broken in production (the real-Clerk job = sign-in) = ROLL BACK; a test fault the merged diff cannot reach = fix forward (deploy.md)"; exit 1; }
[ $red = 1 ] && { say "RESULT: RED — the deploy failed; production answered the probe above: judge the impact (deploy.md) — roll back only for an outage or many users hit, else fix forward before the next merge in this repo"; exit 1; }
[ $broken = 1 ] && { say "RESULT: BROKEN — verify by hand; do not merge the next item"; exit 2; }
[ $review = 1 ] && { say "RESULT: REVIEW — attribute every REVIEW line above before the next merge in this repo"; exit 3; }
say "RESULT: clean"
}
main "$@"
