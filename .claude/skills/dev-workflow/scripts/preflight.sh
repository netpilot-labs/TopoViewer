#!/usr/bin/env bash
# preflight.sh [--vm <name>] — one command at session start and at every board pickup: checks the tools a
# NetPilot session relies on and prints ONE PASS/FAIL/SKIP line each. It never fixes anything (the fix is yours,
# the line tells you which). Why (Lin, 2026-10-04; board 31 close): 14 parallel lanes each discovered the same
# missing scope, logged-out CLI or stopped container mid-task, after the worktree and the PR existed.
#
# Lines: gh login + the `project` scope · gcloud account + project netpilot-ai + an IAP SSH probe to --vm (default
#   linzhu-vm; only Lin's own VM or a golden-setup-* bench is ever probed — never a customer VM; a stopped target is
#   SKIP, not FAIL) · db-access ro query · NETPILOT_DB_ADMIN_URL set/placeholder (never printed) · railway login ·
#   NetPilot-2-Backend/.env.prod · the backend venv runs · Docker daemon · local Postgres container netpilot-db ·
#   `timeout` (macOS lacks it — SKIP with the `gtimeout` / perl-alarm hint while perl exists; FAIL only with neither).
# Exit: 0 all PASS/SKIP · 1 any FAIL. Every external call is bounded with a perl alarm, so a hung CLI cannot hang this.
main() {
set -uo pipefail
VM=linzhu-vm; PROJECT=netpilot-ai
while [ $# -gt 0 ]; do case "$1" in --vm) VM=$2; shift 2;; -h|--help) sed -n '2,12p' "$0"; exit 0;; *) echo "unknown arg $1" >&2; exit 2;; esac; done
S=$(cd "$(dirname "$0")" && pwd); ws=$(cd "$S/../../../.." && pwd); [ -d "$ws/NetPilot-2-Backend/.git" ] || ws=$(cd "$ws/.." && pwd)
ws=${WORKSPACE:-$ws}; BE="$ws/NetPilot-2-Backend"; DBSH="$ws/.claude/skills/db-access/scripts/db.sh"
fail=0
# the bound uses whatever this host has — timeout, gtimeout, else a perl alarm; none = one FAIL up front, no probe runs unbounded
if command -v timeout >/dev/null 2>&1; then bounded() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then bounded() { gtimeout "$@"; }
elif command -v perl >/dev/null 2>&1; then bounded() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV or exit 127' "$s" "$@"; }
else printf 'FAIL  %-28s %s\n' "timeout" "no timeout, gtimeout or perl on this host — nothing can be bounded: brew install coreutils"; exit 1; fi
ok()   { printf 'PASS  %-28s %s\n' "$1" "${2:-}"; }
bad()  { printf 'FAIL  %-28s %s\n' "$1" "${2:-}"; fail=1; }
skip() { printf 'SKIP  %-28s %s\n' "$1" "${2:-}"; }

# gh: logged in, and the `project` scope the board commands need (`gh auth refresh -s project` adds it)
st=$(bounded 20 gh auth status --active -h github.com 2>&1); strc=$?   # --active: the account later gh calls use, not every configured one (Codex R1)
if [ $strc = 0 ] && grep -q 'Logged in to github.com' <<< "$st"; then
  acct=$(sed -n 's/.*Logged in to github.com account \([^ ]*\).*/\1/p' <<< "$st" | head -1)
  if grep -q "'project'" <<< "$st"; then ok "gh auth + project scope" "$acct"; else bad "gh auth + project scope" "$acct logged in, no 'project' scope: gh auth refresh -s project"; fi
else bad "gh auth + project scope" "not logged in (gh auth login)"; fi

# gcloud: account, project, and an IAP SSH probe to a VM that is Lin's own or a bench (customer VMs are never probed)
acc=$(bounded 20 gcloud config get-value account 2>/dev/null); prj=$(bounded 20 gcloud config get-value project 2>/dev/null)
[ -n "$acc" ] && ok "gcloud account" "$acc" || bad "gcloud account" "none (gcloud auth login)"
[ "$prj" = "$PROJECT" ] && ok "gcloud project" "$prj" || bad "gcloud project" "'${prj:-unset}' (gcloud config set project $PROJECT)"
case "$VM" in linzhu-vm|golden-setup-*)
  vrow=$(bounded 30 gcloud compute instances list --project "$PROJECT" --filter="name=$VM" --format='value(status,zone.basename())' 2>/dev/null); vrc=$?
  read -r vstat vzone <<< "$vrow"
  if [ $vrc != 0 ]; then bad "IAP SSH probe ($VM)" "instance list unreadable (rc=$vrc): gcloud auth / project"
  elif [ -z "${vstat:-}" ]; then bad "IAP SSH probe ($VM)" "instance not found in $PROJECT"
  elif [ "$vstat" != RUNNING ]; then skip "IAP SSH probe ($VM)" "instance is $vstat — start it, or --vm <a running golden-setup-*>"
  elif [ ! -f "$HOME/.ssh/google_compute_engine" ]; then skip "IAP SSH probe ($VM)" "no ~/.ssh/google_compute_engine yet — gcloud compute ssh would CREATE and upload a key; run it by hand once, then re-run"
  elif bounded 90 gcloud compute ssh "$VM" --zone "$vzone" --project "$PROJECT" --tunnel-through-iap --quiet --command true >/dev/null 2>&1; then ok "IAP SSH probe ($VM)" "$vzone"
  else bad "IAP SSH probe ($VM)" "ssh via IAP failed ($vzone): gcloud auth login / IAP permission / firewall"; fi;;
  *) bad "IAP SSH probe ($VM)" "refused: only linzhu-vm or a golden-setup-* bench is probed, never a customer VM";;
esac

# db-access: the read-only path answers, and the admin URL is a real postgres URL or a placeholder (its value is never printed)
if [ -x "$DBSH" ]; then
  dbout=$(bounded 30 "$DBSH" ro-raw 'select 1' 2>/dev/null); dbrc=$?   # status AND output: a probe that printed, then hung or died, is not a PASS (Codex R7)
  if [ $dbrc = 0 ] && [ "$(tr -d '[:space:]' <<< "$dbout")" = 1 ]; then ok "db.sh ro 'select 1'" "1"; else bad "db.sh ro 'select 1'" "no clean answer (rc=$dbrc; db-access SKILL.md: .env, direct endpoint, psql@14)"; fi
  envf=${NETPILOT_DB_ENV:-}; [ -n "$envf" ] || for c in "$ws/.claude/skills/db-access/.env"; do [ -f "$c" ] && envf=$c; done
  adm=$( [ -n "$envf" ] && [ -f "$envf" ] && sed -n 's/^[[:space:]]*NETPILOT_DB_ADMIN_URL=//p' "$envf" | tail -1 | tr -d '"'"'" )
  if [ -z "$adm" ]; then skip "NETPILOT_DB_ADMIN_URL" "unset (owner writes are gated anyway — db-access)"
  elif [[ "$adm" == *-pooler* ]]; then bad "NETPILOT_DB_ADMIN_URL" "pooler host — db.sh refuses it; use the direct endpoint (db-access)"
  elif [[ "$adm" =~ ^postgres(ql)?://[^@]+@[^/]+/ ]] && [[ "$adm" != *placeholder* ]] && [[ "$adm" != *example* ]] && [[ "$adm" != *'<'* ]] && [[ "$adm" != *'>'* ]]; then ok "NETPILOT_DB_ADMIN_URL" "set (real postgres URL, direct endpoint)"
  else bad "NETPILOT_DB_ADMIN_URL" "placeholder (an <angle-bracket> or example value, as in .env.example) / not a postgres URL"; fi
else bad "db.sh ro 'select 1'" "$DBSH missing or not executable"; fi

# railway, env file, venv
rw=$(bounded 20 railway whoami 2>&1); rwrc=$?; [ $rwrc = 0 ] && grep -q 'Logged in as' <<< "$rw" && ok "railway whoami" "$(sed -n 's/.*Logged in as \([^ ]*\).*/\1/p' <<< "$rw" | head -1)" || bad "railway whoami" "not logged in (railway login)"
[ -f "$BE/.env.prod" ] && ok "NetPilot-2-Backend/.env.prod" "present" || bad "NetPilot-2-Backend/.env.prod" "missing"
if [ -x "$BE/.venv/bin/python" ] && (cd "$BE" && bounded 30 .venv/bin/python -c 'import fastapi, claude_agent_sdk, alembic' 2>/dev/null); then ok "backend venv" "$(cd "$BE" && .venv/bin/python -c 'import sys; print(sys.version.split()[0])')"
else bad "backend venv" "cd NetPilot-2-Backend && uv sync --all-groups"; fi

# docker daemon, then the local Postgres container the unit suite and the probe lab need
if bounded 15 docker info >/dev/null 2>&1; then ok "docker daemon" "up"
  r=$(bounded 10 docker inspect -f '{{.State.Running}}' netpilot-db 2>/dev/null)
  [ "$r" = true ] && ok "postgres container netpilot-db" "running" || bad "postgres container netpilot-db" "${r:-absent} (cd NetPilot-2-Backend && docker-compose up -d postgres migrations — NEVER bare up -d)"
else bad "docker daemon" "not running (open Docker Desktop)"; bad "postgres container netpilot-db" "docker is down"; fi

# `timeout`: a GNU coreutils command; macOS ships none — scripts here use a perl alarm instead
if command -v timeout >/dev/null 2>&1; then ok "timeout" "$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then ok "timeout" "gtimeout only ($(command -v gtimeout)) — write 'gtimeout' or the perl alarm, never 'timeout'"
else skip "timeout" "absent (macOS) — bound commands with perl -e 'alarm shift; exec @ARGV or exit 127' <secs> <cmd…> (shell.md), or brew install coreutils → gtimeout"
fi

[ $fail = 0 ] && echo "preflight: all PASS/SKIP" || echo "preflight: FAIL lines above — fix them before the worktree (nothing was changed)"
exit $fail
}
main "$@"
