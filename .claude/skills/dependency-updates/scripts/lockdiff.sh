#!/usr/bin/env bash
# lockdiff.sh — lockfile audit (mechanics §4): which resolved packages MOVED on a branch,
# marked LISTED (named in the Renovate PR table) or UNLISTED (a transitive the branch
# re-resolved inside ranges). With a second branch, prints the moves the two SHARE — the
# suspects when sibling PRs fail identically (FE#337/#338, 2026-09-08).
#
# Usage (inside the repo checkout, refs fetched):
#   lockdiff.sh <base-ref> <branch-ref> [--pr N --repo owner/name] [--also <branch2-ref>]
# Detects pnpm-lock.yaml or uv.lock automatically.
set -euo pipefail
base=${1:?base-ref}; branch=${2:?branch-ref}; shift 2
pr=""; repo=""; also=""
while [ $# -gt 0 ]; do case "$1" in
  --pr) pr=$2; shift 2;; --repo) repo=$2; shift 2;; --also) also=$2; shift 2;;
  *) echo "unknown arg $1" >&2; exit 2;; esac; done

if git cat-file -e "$base:pnpm-lock.yaml" 2>/dev/null; then
  keys() { git show "$1:pnpm-lock.yaml" | awk '/^packages:/{p=1;next} /^snapshots:/{p=0} p && /^  [^ ]/{gsub(/^  /,""); gsub(/:$/,""); gsub(/\x27/,""); print}' | sort -u; }
elif git cat-file -e "$base:uv.lock" 2>/dev/null; then
  keys() { git show "$1:uv.lock" | awk '/^\[\[package\]\]/{n="";v=""} /^name = /{gsub(/name = |"/,""); n=$0} /^version = /{gsub(/version = |"/,""); v=$0; if(n!="") print n"@"v}' | sort -u; }
else
  echo "no pnpm-lock.yaml or uv.lock at $base" >&2; exit 2
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
keys "$base" > "$tmp/base"; keys "$branch" > "$tmp/branch"
comm -13 "$tmp/base" "$tmp/branch" > "$tmp/added"
comm -23 "$tmp/base" "$tmp/branch" > "$tmp/removed"

listed="$tmp/listed"; : > "$listed"
if [ -n "$pr" ]; then
  gh pr view "$pr" ${repo:+--repo "$repo"} --json body --jq .body |
    sed -n -E 's/^\| \[([^]]+)\].*/\1/p' | sed 's/&#8203;//g' | sort -u > "$listed"
fi
name_of() { local key=${1%%(*}; echo "${key%@*}"; }   # strip the trailing @version (scoped names keep their leading @)
echo "moved on $branch vs $base: $(wc -l < "$tmp/added" | tr -d ' ') added/changed, $(wc -l < "$tmp/removed" | tr -d ' ') removed"
while read -r k; do
  [ -z "$k" ] && continue
  n=$(name_of "$k")
  if [ -s "$listed" ] && grep -qxF "$n" "$listed"; then tag=LISTED; else tag=UNLISTED; fi
  old=$(awk -v name="$n" 'index($0,name"@")==1 {print substr($0,length(name)+2)}' "$tmp/base" | tr '\n' ',' | sed 's/,$//')
  printf '  %-9s %s   (was %s)\n' "$tag" "$k" "${old:-absent}"
done < "$tmp/added"
[ -s "$tmp/removed" ] && { echo "removed:"; sed 's/^/  /' "$tmp/removed"; }

if [ -n "$also" ]; then
  keys "$also" > "$tmp/also"; comm -13 "$tmp/base" "$tmp/also" > "$tmp/added2"
  echo "shared moves with $also (suspects):"
  comm -12 "$tmp/added" "$tmp/added2" | sed 's/^/  /'
fi
