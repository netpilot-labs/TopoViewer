#!/usr/bin/env bash
# lessons-lint.sh [<skill-dir>] — keeps dev-workflow's phase files lean and navigable.
#
# Runs in the learning pass (skill-maintenance, Shipped step) and on any dev-workflow PR.
# HARD failures (exit 1): a file named in SKILL.md's phase table that does not exist; a stale
#   section anchor (`§`) inside the skill (sections are named, never numbered, since board 30);
#   two bullets across files opening with the same 50 chars (a restated rule — keep ONE, point).
# WARNINGS (exit 0, printed): a file over its cap (caps are SOFT targets — Lin, 2026-09-27: a
#   battle-tested rule that must stay may run over; at the cap, cut or extract a concern to its
#   own file, then add); a lesson bullet
#   of 3+ lines without a provenance tag (`#123`, `2026-09-27`, `Lin,`) — a story, not a rule; a bullet
#   longer than BULLET_MAX lines; fenced blocks (templates, commands) are skipped. Short untagged bullets (procedure steps) are only counted.
# Caps: SKILL.md 250 lines, every phase file 200 (Lin, 2026-10-01 — raised from the board 30
# per-file caps of 25–150 (#17), which made every learning pass a prune; the bullet rules below
# stay, they are what keeps the files concise). BULLET_MAX=6 because the longest surviving
# battle-tested bullets (Vercel outage recovery, the CLI-less Railway watch) wrap at 5–6 lines
# of 120 chars; anything longer is a story, which belongs in memory.
main() {
set -uo pipefail
DIR=${1:-$(cd "$(dirname "$0")/.." && pwd)}
SKILL_CAP=250; FILE_CAP=200
BULLET_MAX=6
hard=0; warn=0
cap_of() { if [ "$1" = "SKILL.md" ]; then echo "$SKILL_CAP"; else echo "$FILE_CAP"; fi; }

# 1. every file the SKILL.md table names exists
for f in $(grep -o '`[a-z-]*\.md`' "$DIR/SKILL.md" | tr -d '`' | sort -u); do
  [ -f "$DIR/$f" ] || { echo "HARD  SKILL.md names $f but it does not exist"; hard=1; }
done
# 2. no numbered-section anchors survive
if grep -n '§' "$DIR"/*.md >/dev/null 2>&1; then
  grep -n '§' "$DIR"/*.md | sed 's/^/HARD  stale § anchor: /'; hard=1
fi
# 3. duplicate bullet openings across files
dups=$(awk 'FNR==1 { fence=0 } /^ {0,3}```/ { fence=!fence; next } !fence && /^- /' "$DIR"/*.md | cut -c1-50 | sort | uniq -d)   # fenced bullets (templates) are not rules
if [ -n "$dups" ]; then
  while IFS= read -r d; do echo "HARD  duplicate bullet opening: $d"; grep -ln -F -- "$d" "$DIR"/*.md | sed 's/^/        in /'; done <<< "$dups"; hard=1
fi
# 4. caps (soft), tags and length per bullet
for path in "$DIR"/*.md; do
  f=$(basename "$path"); lines=$(wc -l < "$path" | tr -d ' '); cap=$(cap_of "$f")
  if [ "$cap" -gt 0 ] && [ "$lines" -gt "$cap" ]; then echo "WARN  $f is $lines lines (soft cap $cap) — cut, or extract a concern to its own file, before adding"; warn=1; fi
  [ "$f" = "SKILL.md" ] && continue   # procedure, not lessons
  awk -v f="$f" -v max="$BULLET_MAX" '
    function flush() { if (n>0) { if (n>max) { printf "WARN  %s:%d bullet is %d lines (max %d): %s\n", f, start, n, max, substr(head,1,60) }
                        if (body !~ /#[0-9]+/ && body !~ /20[0-9][0-9]-[0-9][0-9]/ && body !~ /Lin,/ && body !~ /board [0-9]+/) { untagged++; if (n>=3) printf "WARN  %s:%d %d-line bullet has no provenance tag (a story?): %s\n", f, start, n, substr(head,1,60) } }
                        n=0; body=""; head="" }
    /^ {0,3}```/ { flush(); fence=!fence; next }   # a fenced block (a template, a command; Markdown allows ≤3 leading spaces) is never a lessons bullet
    fence { next }
    /^- / { flush(); start=NR; n=1; head=$0; body=$0; next }
    /^  / && n>0 { n++; body=body" "$0; next }
    { flush() }
    BEGIN { untagged=0; fence=0 }
    END { flush(); if (untagged>0) printf "note  %s: %d untagged bullet(s) — procedure lines are fine, lessons carry a tag\n", f, untagged }' "$path" > /tmp/lint.$$; if [ -s /tmp/lint.$$ ]; then cat /tmp/lint.$$; grep -q '^WARN' /tmp/lint.$$ && warn=1; fi; rm -f /tmp/lint.$$
done
# prune cadence (skill-maintenance): commits touching this skill since the last prune (a commit whose subject
# says "prune:" or "restructure into") — prune first at 10; evidence for reviews, never a gate (#26).
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  last=$(git -C "$DIR" log -1 -E --format=%H --grep='^prune:|restructure into' -- . 2>/dev/null)
  if [ -n "$last" ]; then n=$(git -C "$DIR" rev-list --count "$last"..HEAD -- . 2>/dev/null); else n=$(git -C "$DIR" rev-list --count HEAD -- . 2>/dev/null); fi
  echo "prune cadence: ${n:-?} commit(s) to this skill since the last prune — prune first at 10"
fi
echo "lessons-lint: $(ls "$DIR"/*.md | wc -l | tr -d ' ') files, $(cat "$DIR"/*.md | wc -l | tr -d ' ') lines, ~$(( $(cat "$DIR"/*.md | wc -c) / 4 )) tokens — hard=$hard warn=$warn"
exit $hard
}
main "$@"
