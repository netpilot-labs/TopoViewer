#!/usr/bin/env bash
# resolved.sh <pkg> [<pkg>…] — the version(s) the LOCKFILE in the current directory actually
# resolved for each package (pnpm-lock.yaml or uv.lock). The cooldown and the audit apply to
# THESE, never to the target you typed: carets resolve the newest in-range release (js-yaml
# 4.3.1→4.3.2 on FE#482; posthog-js 1.424.1→1.428.7 on the runtime-a lane, 2026-09-09).
# Prints "<pkg> <version>[ <version>…]" per line; exit 1 if a package is absent.
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: resolved.sh <pkg> [<pkg>…]" >&2; exit 2; }
rc=0
for pkg in "$@"; do
  if [ -f pnpm-lock.yaml ]; then
    # packages: section only — the overrides: block also carries "<pkg>@<major>: <range>" lines
    # that read as bogus versions (js-yaml "3 3.15.2 4 4.3.2" on MKT#179, 2026-09-09)
    v=$(awk '/^packages:/{p=1;next} /^snapshots:/{p=0} p' pnpm-lock.yaml | grep -E "^  '?$(printf '%s' "$pkg" | sed 's/[.[\*^$+?/]/\\&/g')@[0-9]" | sed -E "s/^  '?//; s/[(:].*//; s/^.*@//" | tr -d "'" | sort -uV | tr '\n' ' ' | sed 's/ *$//')
  elif [ -f uv.lock ]; then
    v=$(awk -v p="$pkg" '/^\[\[package\]\]/{n=""} /^name = /{gsub(/name = |"/,""); n=$0} /^version = /{gsub(/version = |"/,""); if(n==p) print $0}' uv.lock | sort -uV | tr '\n' ' ' | sed 's/ *$//')
  else echo "no pnpm-lock.yaml or uv.lock here" >&2; exit 2; fi
  [ -n "$v" ] && echo "$pkg $v" || { echo "$pkg ABSENT"; rc=1; }
done
exit $rc
