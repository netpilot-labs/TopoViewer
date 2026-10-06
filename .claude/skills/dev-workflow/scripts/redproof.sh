#!/usr/bin/env bash
# redproof.sh — ONE red-proof run (test.md): run the test GREEN, mutate a file, run it again bounded, ALWAYS put the file back.
#   redproof.sh <file> --ref <git-ref> [--bound <sec>] -- <test command…>     the file as it is at <git-ref> (fix reverted)
#   redproof.sh <file> --sub <old> <new> [--bound <sec>] -- <test command…>   one exact-once replacement (a mutation)
# Run it from the repo/worktree root, once per mutation; several fit one tool round. It encodes what hand-rolled proofs
# got wrong: the command must PASS on the unmutated file first — a test that is already failing proves nothing (BE#962:
# 18/18 "red" with 6 of the tests failing from a fixture bug) — the revert happens in the same run even when the test
# hangs or this script is interrupted (the test's process group is ended first; BE PR#904 left a mutated file on disk), the
# mutated module's stale .pyc is removed before and after (BE#260), each run is bounded by a watchdog of this script's
# own (macOS has no `timeout`; an alarm inside the test dies with a test that ignores SIGALRM), and the
# restore is byte-checked. Stdin given as a file or a pipe is replayed to both runs. The command's last lines are printed: YOU read why it is red — "no tests ran" or an import
# error proves nothing.
# Exit: 0 RED seen (the command passed before the mutation, failed on the mutated file) and the file is restored
#       1 NOT RED (it passed on the mutated file)
#       3 no proof: the command was NOT GREEN before the mutation (the file is never mutated), the bound expired, or
#       the test command was killed by a signal (rc > 128: OOM, an interrupt)
#       2 usage, mutation did not apply, the test command could not be started (rc 126/127), or the restore
#       could not be verified.
set -uo pipefail
usage() { sed -n '2,4p' "$0" >&2; exit 2; }
f=${1:-}; [ -f "$f" ] || usage; shift
case "${1:-}" in
  --ref) ref=${2:?git ref}; mode=ref; shift 2;;
  --sub) old=${2:?old}; new=${3?new}; mode=sub; shift 3;;
  *) usage;;
esac
bound=300; [ "${1:-}" = --bound ] && { bound=${2:?seconds}; shift 2; }
[ "${1:-}" = -- ] && [ $# -ge 2 ] || usage; shift
snap=$(mktemp) || exit 2; out=$(mktemp) || exit 2; mut=$(mktemp) || exit 2; cp -p "$f" "$snap" || exit 2
echo "redproof: snapshot of $f at $snap (only a kill -9 of this script needs it: cp it back by hand)"
d=$(dirname "$f"); stem=$(basename "$f"); stem=${stem%.*}
purge() { rm -f "$d/__pycache__/$stem".*.pyc 2>/dev/null; }
restore() { cp -p "$snap" "$f"; purge; cmp -s "$snap" "$f"; }
child=""; wd=""; expired="$out.expired"; in=/dev/null
stop() {   # end the test command's whole process group (TERM, 10 s, KILL) and reap it — BEFORE any restore
  [ -n "$wd" ] && kill "$wd" 2>/dev/null
  [ -n "$child" ] || return 0; kill -TERM -- "-$child" 2>/dev/null
  local i=0; while kill -0 -- "-$child" 2>/dev/null && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
  kill -KILL -- "-$child" 2>/dev/null; wait "$child" 2>/dev/null
}
# the snapshot is deleted only after a VERIFIED restore; a failed one keeps it and says where it is
trap 'if restore; then rm -f "$snap"; else echo "redproof: RESTORE NOT VERIFIED — $f differs from its snapshot, kept at $snap" >&2; rm -f "$out" "$expired" "$mut" "${in#/dev/null}"; exit 2; fi; rm -f "$out" "$expired" "$mut" "${in#/dev/null}"' EXIT
trap 'stop; exit 130' INT TERM
# stdin given as a file or a pipe (`… -- bash -s < probe.sh`) is read ONCE and replayed: both runs get the same input
if [ -f /dev/stdin ] || [ -p /dev/stdin ]; then in=$(mktemp) || exit 2; cat > "$in"; fi
# the mutated copy is built BESIDE the file, so a mutation that does not apply is refused before any test run
if [ $mode = ref ]; then git show "$ref:./$f" > "$mut" || { echo "redproof: cannot read $f at $ref" >&2; exit 2; }
else OLD=$old NEW=$new python3 - "$f" "$mut" <<'PY' || { echo "redproof: --sub must match exactly once" >&2; exit 2; }
import os, sys
s = open(sys.argv[1]).read(); old = os.environ["OLD"]
sys.exit(1) if s.count(old) != 1 else open(sys.argv[2], "w").write(s.replace(old, os.environ["NEW"]))
PY
fi
cmp -s "$snap" "$mut" && { echo "redproof: the mutation changed nothing in $f" >&2; exit 2; }
run() {   # one bounded run of the test command; sets rc (142 = the bound expired)
  rm -f "$expired"
  # asynchronous + its own process group: an INT/TERM that reaches only this script still ends the test before the file
  # is put back (a foreground child would defer the trap until the bound), and nothing of the test outlives the run
  perl -e 'setpgrp(0, 0); exec @ARGV or exit 127' "$@" > "$out" 2>&1 <&0 & child=$!
  # the bound is THIS script's: at the deadline the watchdog marks the run expired and ends the group (TERM, 5 s, KILL)
  perl -e '($b, $g, $m) = @ARGV; sleep $b; open(F, ">", $m) and close F; kill "TERM", -$g; sleep 5; kill "KILL", -$g' "$bound" "$child" "$expired" & wd=$!
  wait "$child"; rc=$?
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  kill -KILL -- "-$child" 2>/dev/null   # whatever the command left running in its group
  [ -e "$expired" ] && rc=142
  child=""; wd=""
}
# GREEN first, on the unmutated file (no stale .pyc of it either)
purge
run "$@" < "$in"
case $rc in
  0) echo "redproof: green before the mutation";;
  126|127) tail -15 "$out"; echo "redproof: the test command did not start (rc=$rc) — no proof ($f untouched)"; exit 2;;
  142) tail -15 "$out"; echo "redproof: BOUND EXPIRED after ${bound}s BEFORE the mutation — no proof ($f untouched)"; exit 3;;
  *) tail -15 "$out"; echo "redproof: NOT GREEN before the mutation (rc=$rc) — no proof: the command already fails on the unmutated $f; fix the test or its fixture first"; exit 3;;
esac
cat "$mut" > "$f" || exit 2
purge
run "$@" < "$in"
tail -15 "$out"
restore || exit 2   # the EXIT trap tries once more, reports, and keeps the snapshot
case $rc in
  0) echo "redproof: NOT RED — the command passed on the mutated $f (restored)"; exit 1;;
  126|127) echo "redproof: the test command did not start (rc=$rc) — no proof ($f restored)"; exit 2;;
  142) echo "redproof: BOUND EXPIRED after ${bound}s — no proof ($f restored; the command's process group was killed)"; exit 3;;
  12[89]|1[3-9][0-9]|2[0-9][0-9]) echo "redproof: the test command was killed by signal $((rc-128)) (rc=$rc) — no proof ($f restored)"; exit 3;;
  *) echo "redproof: RED rc=$rc on the mutated $f, green before it (restored, byte-identical) — read the lines above for WHY"; exit 0;;
esac
