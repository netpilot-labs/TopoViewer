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
#   containerlab-mcp / netpilot-skills / netpilot-probe-lab   no deploy on merge: ONE RESULT line (with the `main`
#                                        push runs for the sha, read once, never waited for), exit 0, no hold recorded.
#                                        A hold already kept for that sha is freed only when those runs are all
#                                        completed/success (or the repo has no workflows).
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
[ ${#sha} -eq 40 ] || { echo "merge sha must be the full 40-char oid (gotchas: never hand-type one)" >&2; exit 2; }
folder=$R; [ "$R" = TopoViewer ] && folder=topoViewer
ws=${WORKSPACE:-$(cd "$(dirname "$0")/../../../.." && pwd)}; [ -d "$ws/$folder/.git" ] || ws=$(cd "$ws/.." && pwd)
red=0; broken=0; review=0; ci_only=""; outage=0
say() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }
SLOT="$(cd "$(dirname "$0")" && pwd)/merge-slot.sh"
# The repo is settled BEFORE the settle trap is armed: a repo with no deploy on merge has nothing to watch and an unknown
# name is a typo — neither may write a hold into a merge slot (`unknown repo` did, as a late BROKEN nobody could clear:
# clab PR#264, 2026-10-02). A hold ALREADY kept for this sha (that stale one; merge.sh's "base moved inside the window")
# is freed only on a verified main — every push run for the sha completed/success on a merge at least RUNS_APPEAR_S old
# (so no workflow's run is still to be minted), or a repo with no workflows; an unreadable, missing, running or failed run
# leaves it held (Codex, skills PR#60). No other holder is touched.
case "$R" in
  NetPilot-2-Backend|NetPilot-2-LB|NetPilot-2-Frontend|netpilot-marketing) ;;
  containerlab-mcp|netpilot-skills|netpilot-probe-lab|netpilot-devops|netpilot-dev|netpilot-lead-desk|netpilot-support-desk|netpilot-marketing-monitor|3rd-party-apps|TopoViewer)
    runs=$(gh api "repos/$OWNER/$R/actions/runs?head_sha=$sha&event=push" --jq '[.workflow_runs[]|"\(.name) \(.status)/\(.conclusion // "-")"]|join(", ")') || runs="UNREADABLE"
    wf=$(gh api "repos/$OWNER/$R/actions/workflows" --jq .total_count) || wf="UNREADABLE"
    # a push run is minted within seconds of the merge; before RUNS_APPEAR_S a green list may still be missing a workflow
    age=$(gh api "repos/$OWNER/$R/commits/$sha" --jq .commit.committer.date | python3 -c 'import sys,datetime,time; print(int(time.time()-datetime.datetime.fromisoformat(sys.stdin.read().strip().replace("Z","+00:00")).timestamp()))' 2>/dev/null) || age=""
    verified=0; RUNS_APPEAR_S=180
    if [ "$wf" = 0 ]; then verified=1; runs="none (the repo has no workflows)"
    elif [ -n "$runs" ] && [ "$runs" != UNREADABLE ] && [[ "$age" =~ ^[0-9]+$ ]] && [ "$age" -ge $RUNS_APPEAR_S ] \
      && ! printf '%s\n' "$runs" | tr ',' '\n' | grep -qvE ' completed/success$'; then verified=1; fi
    say "RESULT: no deploy on merge for $R — nothing to watch. default-branch push run(s) for ${sha:0:8}: ${runs:-none yet} (read once: follow any that is not completed/success); the repo's own post-merge step is in deploy.md"
    if [ $verified = 1 ]; then [ -x "$SLOT" ] && "$SLOT" settle "$OWNER/$R" "$sha" clean
    else [ -x "$SLOT" ] && "$SLOT" peek "$OWNER/$R" | grep -q . && say "main is not verified for ${sha:0:8}: a merge-slot hold kept for this sha stays — re-run this once the run is green"; fi
    exit 0;;
  *) echo "unknown repo $R — deploy repos: NetPilot-2-Backend NetPilot-2-LB NetPilot-2-Frontend netpilot-marketing; no deploy on merge: containerlab-mcp netpilot-skills netpilot-probe-lab netpilot-devops netpilot-dev netpilot-lead-desk netpilot-support-desk netpilot-marketing-monitor 3rd-party-apps topoViewer" >&2; exit 2;;
esac
# merge-slot.sh settle on EVERY exit: clean frees the repo's merge slot; RED/BROKEN/REVIEW (an interrupted watch is
# BROKEN) is written into it and it stays held until read (skills PR#55). SLOT's path was resolved before any cd.
slot_result() { case $1 in 0) [ $skip_sentry = 1 ] && echo clean-skip || echo clean;; 3) echo REVIEW;; 1) [ $review = 1 ] && echo RED+REVIEW || echo RED;; *) [ $review = 1 ] && echo BROKEN+REVIEW || echo BROKEN;; esac; }
trap 'rc=$?; [ -x "$SLOT" ] && "$SLOT" settle "$OWNER/$R" "$sha" "$(slot_result $rc)"' EXIT
trap 'exit 2' INT TERM

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
      SUCCESS) say "railway $svc: SUCCESS for ${sha:0:8}"; return;;
      FAILED|CRASHED) say "RED: railway $svc deployment $st for ${sha:0:8}"; red=1; return;;
      NEEDS_APPROVAL) say "BROKEN: railway deployment NEEDS_APPROVAL (dev-workflow/deploy.md has the GraphQL approve)"; broken=1; return;;
      PARSE) bad=$((bad+1)); if [ $bad -ge $PARSE_TOLERANCE ]; then say "BROKEN: railway CLI output unparseable ${bad}× in a row — unauthenticated or CLI outage; run it in the foreground (dev-workflow/deploy.md)"; broken=1; return; fi; say "railway $svc: transient unparseable response ($bad/$PARSE_TOLERANCE) …"; sleep 20;;
      *) [ $(date +%s) -gt $deadline ] && { say "BROKEN: railway $svc still $st after ${DEPLOY_TIMEOUT_MIN} min"; broken=1; return; }; say "railway $svc: $st …"; sleep 30;;
    esac
  done
}

main_run_wait() {  # backend: the push run on main for this sha
  local deadline=$(( $(date +%s) + 25*60 )) id st
  while :; do
    id=$(gh api "repos/$OWNER/$R/actions/runs?head_sha=$sha&event=push" --jq '.workflow_runs[0].id // empty')
    [ -n "$id" ] && break; [ $(date +%s) -gt $deadline ] && { say "BROKEN: no push run on main for ${sha:0:8}"; broken=1; return; }; sleep 20
  done
  while :; do
    st=$(gh run view "$id" -R "$OWNER/$R" --json status,conclusion --jq '"\(.status)/\(.conclusion)"')
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

vercel_wait() {  # route url [version-url]
  local deadline=$(( $(date +%s) + DEPLOY_TIMEOUT_MIN*60 )) appear=$(( $(date +%s) + VERCEL_APPEAR_MIN*60 )) id st
  while :; do
    id=$(gh api "repos/$OWNER/$R/deployments?sha=$sha&environment=production" --jq '.[0].id // empty')
    [ -n "$id" ] && break
    [ $(date +%s) -gt $appear ] && { say "BROKEN: no Vercel deployment for ${sha:0:8} after ${VERCEL_APPEAR_MIN} min — event miss; push an empty lz-networks-authored commit (dev-workflow/deploy.md)"; broken=1; return; }
    sleep 15
  done
  while :; do
    st=$(gh api "repos/$OWNER/$R/deployments/$id/statuses" --jq '.[0].state // "pending"')
    case "$st" in
      success) say "vercel deployment $id: success"; break;;
      failure|error) say "RED: vercel deployment $id: $st (the fix is NOT live)"; red=1; probe_samples "$1" 15; return;;
      *) [ $(date +%s) -gt $deadline ] && { say "BROKEN: vercel deployment $id still $st"; broken=1; return; }; sleep 20;;
    esac
  done
  probe_samples "$1" 15  # also run after a FAILED deploy above, so the RESULT line never guesses
  if [ -n "${2:-}" ]; then
    # The CDN can still answer with the previous deployment's stamp for a few seconds after the
    # deployment reports success (FE#499: previous sha at +1 s, new sha at +2 s, 2026-09-11) —
    # and it ignores query strings on static files, so retry rather than cache-bust.
    local v="" i
    for i in 1 2 3 4 5 6; do
      v=$(curl -fsS -m 15 -H "Cache-Control: no-cache" "$2" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>/dev/null) || v=""
      [ "$v" = "$sha" ] && break; sleep 10
    done
    if [ "$v" = "$sha" ]; then say "version stamp $v"
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
    railway_wait NetPilot-2-Backend; dep_red=$red; [ $broken = 0 ] && { railway_health; [ $dep_red = 0 ] && main_run_wait; }
    sentry_new netpilot-backend;;
  NetPilot-2-LB)
    railway_wait NetPilot-2-LB; [ $broken = 0 ] && railway_health;;
  NetPilot-2-Frontend)
    vercel_wait https://app.netpilot.io/sign-in https://app.netpilot.io/version.json; sentry_new netpilot-frontend
    # capture signal (mechanics §8): REVIEW on 0 events, "not configured" without a personal key — never red by itself
    # posthog-signal.sh stays with dependency-updates (its owner); a consumer that does not vendor
    # that skill (netpilot-dev) gets a note instead of a dead path (board 30 Phase 2, 2026-09-28).
    phs="$(dirname "$0")/../../dependency-updates/scripts/posthog-signal.sh"
    if [ -x "$phs" ]; then
      pout=$("$phs" --window 15m); prc=$?; say "$pout"
      # the helper's status is the gate's (Codex, netpilot-skills PR#45): 2 = unavailable/failed → BROKEN; 1 = 0 events → REVIEW (exit 3)
      case $prc in 0) ;; 2) say "BROKEN: posthog signal unavailable — no capture signal read"; broken=1;; 1) review=1;; *) say "BROKEN: posthog signal helper exited $prc — no capture signal read"; broken=1;; esac
    else say "posthog signal: dependency-updates/scripts/posthog-signal.sh not vendored here — skipped (a consumer without that skill runs no dependency gate)"; fi;;
  netpilot-marketing)
    vercel_wait https://www.netpilot.io/;;
esac
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
