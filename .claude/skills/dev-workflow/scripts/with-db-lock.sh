#!/usr/bin/env bash
# with-db-lock.sh <tag> <command…> — ONE consumer of the local Postgres (`netpilot-db`) at a time, served in ARRIVAL order.
# Why: a backend `pytest tests/unit` and a probe-lab run share that server, and two at once make BOTH look broken
# (TooManyConnectionsError, missing relations — LAB#59). Board 31's nine parallel lanes used a first-to-poll-wins mkdir
# lock: a 3-minute job waited 40+ min while later arrivals took the lock twice (2026-10-02). This one queues by ticket.
# How to use it:
#   - wrap every backend unit-suite run and every probe run; <tag> = your issue id (it is what the waiters print);
#   - ONE hold per step: put the red-proof runs + the full suite (or both probe arms) in one script and wrap that;
#   - launch it `run_in_background` with the LONGEST timeout from the start — a foreground call is moved to the
#     background at 10 min and killed at its limit while it is still queued (two lanes lost a run that way).
# Exit: the command's own status · 97 gave up after WAIT_MAX_S (default 7200) · 2 usage.
# State (machine-local): $NETPILOT_DB_LOCK (default /tmp/netpilot-db.lock.d, a mkdir lock holding pid + tag) and its
# queue ${NETPILOT_DB_LOCK%.d}.q. The lock names TWO owners: this wrapper (`wrapper`) and the command's process group
# (`pid` — the command runs in its OWN group). A waiter reclaims the lock only when BOTH are gone, so a live wrapper is
# never raced by a takeover while it releases, and a wrapper killed outright leaves the lock with the command (and any
# stray descendant) until that group is gone. INT/TERM here ends the whole group — a helper shell's pytest included —
# before the lock goes. A dead waiter's ticket and a lock directory that never got an owner written (GRACE polls) are
# dropped by whoever polls next (Codex, skills PR#60).
set -uo pipefail
[ $# -ge 2 ] || { echo "usage: with-db-lock.sh <tag> <command…>" >&2; exit 2; }
tag=$(printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'); shift
lock=${NETPILOT_DB_LOCK:-/tmp/netpilot-db.lock.d}; q=${lock%.d}.q; POLL=${POLL_S:-5}; WAIT_MAX_S=${WAIT_MAX_S:-7200}
mkdir -p "$q" || exit 2
ticket="$q/$(date +%s).$(printf '%07d' $$).$tag"; : > "$ticket"; held=0
GRACE=${GRACE_POLLS:-6}; child=""; nopid=0
alive() { kill -0 "$1" 2>/dev/null || kill -0 -- "-$1" 2>/dev/null; }   # the pid, or any member of the group it leads
cleanup() {
  rm -f "$ticket"; [ $held = 1 ] || return 0
  # no waiter can have reclaimed the lock: it names this wrapper, and this wrapper is alive until it has released it
  [ "$(cat "$lock/wrapper" 2>/dev/null)" = "$$" ] || return 0
  if [ -n "$child" ] && kill -0 -- "-$child" 2>/dev/null; then
    echo "with-db-lock: $tag — processes of the command are still running (group $child): the lock stays until they are gone" >&2
  else rm -f "$lock/pid" "$lock/tag" "$lock/wrapper"; rmdir "$lock" 2>/dev/null; fi
}
stop_group() {   # TERM the command's whole group, poll it for 20 s, KILL what is left, then reap (a command that
  # ignores TERM must not block here: the poll comes BEFORE the wait — Codex, skills PR#60)
  [ -n "$child" ] || return 0; kill -TERM -- "-$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null
  local i=0; while kill -0 -- "-$child" 2>/dev/null && [ $i -lt 20 ]; do sleep 1; i=$((i+1)); done
  kill -KILL -- "-$child" 2>/dev/null; wait "$child" 2>/dev/null
}
trap cleanup EXIT; trap 'stop_group; exit 143' INT TERM
waited=0
while :; do
  for t in "$q"/*; do   # drop tickets whose waiter died; names sort by arrival second, then pid
    [ -e "$t" ] || continue; p=${t##*/}; p=${p#*.}; p=${p%%.*}; kill -0 "$((10#$p))" 2>/dev/null || rm -f "$t"
  done
  first=$(ls "$q" | sort | head -1)
  if [ "$q/$first" = "$ticket" ]; then
    if mkdir "$lock" 2>/dev/null; then echo $$ > "$lock/wrapper"; echo "$tag" > "$lock/tag"; held=1; rm -f "$ticket"; break; fi
    owner=$(cat "$lock/pid" 2>/dev/null || true); wr=$(cat "$lock/wrapper" 2>/dev/null || true)
    if [ -z "$owner$wr" ]; then nopid=$((nopid+1)); else nopid=0; fi
    if { [ -n "$owner$wr" ] && { [ -z "$wr" ] || ! alive "$wr"; } && { [ -z "$owner" ] || ! alive "$owner"; }; } || [ $nopid -ge "$GRACE" ]; then
      echo "with-db-lock: holder ${owner:-${wr:-<no owner written>}} ($(cat "$lock/tag" 2>/dev/null)) is gone — taking over" >&2
      rm -f "$lock/pid" "$lock/tag" "$lock/wrapper"; rmdir "$lock" 2>/dev/null; nopid=0; continue
    fi
  fi
  [ $((waited % 60)) -eq 0 ] && echo "with-db-lock: $tag waiting ${waited}s — held by $(cat "$lock/tag" 2>/dev/null || echo '?'), queue: $(ls "$q" | sort | sed 's/^[0-9]*\.[0-9]*\.//' | tr '\n' ' ')" >&2
  sleep "$POLL"; waited=$((waited+POLL))
  [ "$waited" -ge "$WAIT_MAX_S" ] && { echo "with-db-lock: $tag gave up after ${WAIT_MAX_S}s" >&2; exit 97; }
done
# the command's process writes ITS OWN group id into the lock before it execs the command: the command never runs
# under a lock that names only this wrapper
perl -e 'setpgrp(0, 0); open(my $f, ">", shift) or exit 126; print $f "$$\n"; close $f; exec @ARGV or exit 127' "$lock/pid" "$@" <&0 & child=$!
wait "$child"
