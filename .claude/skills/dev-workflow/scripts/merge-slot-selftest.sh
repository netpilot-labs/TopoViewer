#!/usr/bin/env bash
# merge-slot-selftest.sh — offline self-test of merge-slot.sh and of postmerge.sh's no-deploy / unknown-repo exits.
# Run it after ANY edit to merge-slot.sh, to the slot calls in a merge.sh, or to postmerge.sh's repo case.
# It works in a temp MERGE_CLAIM_DIR with a stub `gh` on PATH: no real slot, no network. Exit 0 = every case passed.
# Why it exists: an acknowledged hold came back after every merge in a no-deploy repo, and postmerge.sh recorded a
# BROKEN hold for a repo it did not know (clab PR#264 → #265 #266 #267 each needed MERGE_SLOT_ACK, 2026-10-02).
set -uo pipefail
SK="$(cd "$(dirname "$0")" && pwd)"; S="$SK/merge-slot.sh"; PM="$SK/postmerge.sh"
T=$(mktemp -d) || exit 2; trap 'rm -rf "$T"' EXIT
export MERGE_CLAIM_DIR="$T/claims"; mkdir -p "$T/bin"
# Stub the actual REST shapes consumed by postmerge and its named-job helper.
# A private clock advances across the bounded wait, so missing/pending CI is
# exercised without a real 25-minute sleep. No external API or real slot is used.
cat > "$T/bin/gh" <<'PYGH'
#!/usr/bin/env python3
import json, os, sys
args=' '.join(sys.argv[1:]); sha='a'*40
if 'commits/' in args and '/pulls' in args: print(7)
elif 'actions/workflows' in args: print(os.environ.get('STUB_WF','0'))
elif 'actions/runs/' in args and '/jobs' in args:
    names=['lint','security','type-check','unit-tests','integration-tests']
    print(json.dumps([{'jobs':[{'name':n,'head_sha':sha,'status':'completed','conclusion':'success'} for n in names]}]))
elif 'actions/runs' in args:
    state=os.environ.get('STUB_RUNS','')
    rows=[]
    if state:
        status='in_progress' if 'in_progress' in state else 'completed'
        conclusion=None if status!='completed' else ('failure' if 'failure' in state else 'success')
        rows=[{'id':10,'path':'.github/workflows/test.yml','head_sha':sha,'head_branch':'main','event':'push','created_at':'2026-01-01T00:00:00Z','status':status,'conclusion':conclusion}]
    print(json.dumps([{'workflow_runs':rows}]))
elif 'commits/' in args: print(os.environ.get('STUB_DATE','2026-01-01T00:00:00Z'))
elif 'repos/netpilot-labs/containerlab-mcp' in args and '.default_branch' in args: print('main')
else: raise SystemExit(2)
PYGH
cat > "$T/bin/date" <<'SHDATE'
#!/bin/sh
if [ "$*" = '+%s' ]; then
  python3 - <<'PYDATE'
import os
from pathlib import Path
p=Path(os.environ['SELFTEST_CLOCK'])
n=int(p.read_text()) if p.exists() else 0
p.write_text(str(n+1600))
print(n)
PYDATE
else exec /bin/date "$@"; fi
SHDATE
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T/bin/gh" "$T/bin/date" "$T/bin/sleep"
export SELFTEST_CLOCK="$T/clock" PATH="$T/bin:$PATH"
R=o/r; D="$MERGE_CLAIM_DIR/o__r"; SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
fail=0; n=0
t() { n=$((n+1)); local name=$1; shift; if "$@" >/dev/null 2>&1; then echo "ok   $n $name"; else echo "FAIL $n $name"; fail=1; fi; }
free() { [ ! -d "${1:-$D}" ]; }
state() { [ "$(cut -d' ' -f1,4 "${2:-$D}/holder" 2>/dev/null)" = "$1" ]; }
hold_broken() { local k; k=$("$S" acquire "$R" 7) && "$S" sha "$R" "$k" "$SHA" && "$S" settle "$R" "$SHA" "${1:-BROKEN}"; }

tok=$("$S" acquire "$R" 7);                 t "acquire takes a free slot" state "7 inflight"
t "a second acquire is refused"             bash -c "! '$S' acquire $R 8"
"$S" release "$R" "$tok";                   t "release (not merged) frees it" free

hold_broken >/dev/null;                     t "a BROKEN watch keeps the slot held" state "7 BROKEN"
t "acquire without the ACK is refused"      bash -c "! '$S' acquire $R 8"
tok=$(MERGE_SLOT_ACK=7 "$S" acquire "$R" 8 2>/dev/null); t "acquire with the ACK takes it" state "8 inflight"
"$S" release "$R" "$tok" 2>/dev/null;       t "ACK run that did NOT merge puts the holder back" state "7 BROKEN"
tok=$(MERGE_SLOT_ACK=7 "$S" acquire "$R" 8 2>/dev/null)
"$S" release "$R" "$tok" merged 2>/dev/null; t "ACK run that MERGED (no deploy watch) clears the hold" free

"$S" settle "$R" "$SHA" BROKEN >/dev/null;  t "a late non-clean re-run records a hold" state "7 BROKEN"
mkdir "$D/ack"; "$S" settle "$R" "$SHA" clean >/dev/null; t "a clean re-run during an ACK handoff does NOT free it" state "7 BROKEN"
rmdir "$D/ack"; "$S" settle "$R" "$SHA" clean >/dev/null;   t "a clean re-run for that sha frees it" free
hold_broken REVIEW >/dev/null; "$S" settle "$R" "$SHA" clean >/dev/null; t "a clean re-run never clears REVIEW lines" state "7 REVIEW"
tok=$(MERGE_SLOT_ACK=7 "$S" acquire "$R" 8 2>/dev/null); "$S" release "$R" "$tok" merged 2>/dev/null

C="$MERGE_CLAIM_DIR/netpilot-labs__containerlab-mcp"
"$S" settle netpilot-labs/containerlab-mcp "$SHA" BROKEN >/dev/null; t "(setup) a stale hold on a no-deploy repo" state "7 BROKEN" "$C"
STUB_WF=2 STUB_RUNS="Tests in_progress/-" "$PM" containerlab-mcp "$SHA" >/dev/null 2>&1; t "postmerge.sh <no-deploy repo>: a RUNNING main run keeps the hold" state "7 BROKEN" "$C"
STUB_WF=2 STUB_RUNS="Tests completed/failure, Lint completed/success" "$PM" containerlab-mcp "$SHA" >/dev/null 2>&1; t "… a FAILED main run keeps a RED hold" state "7 RED" "$C"
STUB_WF=2 STUB_RUNS="" "$PM" containerlab-mcp "$SHA" >/dev/null 2>&1; t "… no run yet keeps it" state "7 BROKEN" "$C"
STUB_WF=2 STUB_RUNS="Tests completed/success" STUB_DATE=$(date -u +%FT%TZ) "$PM" containerlab-mcp "$SHA" >/dev/null 2>&1; t "… a green run on a merge seconds old keeps it (a second workflow's run may not exist yet)" state "7 BROKEN" "$C"
out=$(STUB_WF=2 STUB_RUNS="Tests completed/success, Docs completed/skipped" "$PM" containerlab-mcp "$SHA" 2>&1); rc=$?
t "… exits 0"                                        [ $rc -eq 0 ]
t "… says there is no deploy on merge"               grep -q 'no deploy on merge' <<< "$out"
t "… green main runs clear the stale hold for that sha" free "$C"
K="$MERGE_CLAIM_DIR/lz-networks__netpilot-skills"
tok=$("$S" acquire lz-networks/netpilot-skills 9); "$PM" netpilot-skills "$SHA" >/dev/null 2>&1
t "… and leaves another PR's in-flight slot alone"   state "9 inflight" "$K"
"$S" release lz-networks/netpilot-skills "$tok"
tok=$("$S" acquire lz-networks/netpilot-skills 7); "$S" sha lz-networks/netpilot-skills "$tok" "$SHA"; "$PM" netpilot-skills "$SHA" >/dev/null 2>&1
t "… and frees a hold kept for that sha in a repo with no workflows (merge.sh: base moved inside the window)" free "$K"
"$PM" no-such-repo "$SHA" >/dev/null 2>&1; rc=$?
t "postmerge.sh <unknown repo> exits 2"              [ $rc -eq 2 ]
t "… and records no hold"                            free "$MERGE_CLAIM_DIR/lz-networks__no-such-repo"

echo "merge-slot-selftest: $n cases, $([ $fail = 0 ] && echo PASS || echo FAIL)"; exit $fail
