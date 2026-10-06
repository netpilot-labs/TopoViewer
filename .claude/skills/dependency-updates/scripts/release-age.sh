#!/usr/bin/env bash
# release-age.sh — age of a published version (SKILL.md always-on rule: hand-made bumps
# respect the fleet's 7-day cooldown; Renovate's minimumReleaseAge cannot see them).
#
# Usage: release-age.sh pypi|npm <pkg> <version> [--security]
# Exit:  0 old enough · 1 too young (blocked unless --security) · 2 lookup failed
# MIN_AGE_DAYS mirrors `minimumReleaseAge: "7 days"` in every fleet renovate.json.
set -uo pipefail
MIN_AGE_DAYS=${MIN_AGE_DAYS:-7}
eco=${1:?pypi|npm}; pkg=${2:?pkg}; ver=${3:?version}; sec=${4:-}
case "$eco" in
  pypi) ts=$(curl -sf "https://pypi.org/pypi/$pkg/$ver/json" | jq -r '.urls[0].upload_time_iso_8601 // empty');;
  npm)  ts=$(npm view "$pkg@$ver" time --json 2>/dev/null | jq -r --arg v "$ver" '.[$v] // empty');;
  *) echo "eco must be pypi or npm" >&2; exit 2;;
esac
[ -z "$ts" ] && { echo "no upload time for $pkg@$ver on $eco" >&2; exit 2; }
t0=$(python3 - "$ts" <<'PYTIME'
import datetime, sys
try:
    value = datetime.datetime.fromisoformat(sys.argv[1].replace('Z', '+00:00'))
    if value.tzinfo is None: raise ValueError('upload time has no timezone')
    print(value.timestamp())
except ValueError as error:
    print('invalid upload timestamp: ' + str(error), file=sys.stderr)
    sys.exit(2)
PYTIME
) || exit 2
now=$(date +%s) || exit 2
age=$(python3 - "$now" "$t0" <<'PYAGE'
import sys
print(int((float(sys.argv[1]) - float(sys.argv[2])) // 86400))
PYAGE
) || exit 2
echo "$pkg@$ver published $ts — ${age}d old (min $MIN_AGE_DAYS)"
if [ "$age" -lt "$MIN_AGE_DAYS" ]; then
  if [ "$sec" = --security ]; then echo "younger than the cooldown; allowed: security-driven"; exit 0; fi
  echo "BLOCKED: younger than the cooldown — wait, or pass --security when a CVE drives the bump"; exit 1
fi
