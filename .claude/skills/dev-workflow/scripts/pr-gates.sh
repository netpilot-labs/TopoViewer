#!/bin/bash
# pr-gates.sh <pr> [--repo owner/name] [--watch [--wait-ci]] [--since <ISO-UTC>] [--quiet]
#   --since    ignore CI runs created before this instant (take it with `date -u` BEFORE the flip /
#              reopen / push); passed through to ci-wait.sh. Without it an OLD successful run on the
#              same head can read as green before the fresh one exists (PR #23 R1, 2026-09-28).
#   --wait-ci  after the verdict lands, chain into ci-wait.sh for the CI half and exit with ITS
#              result — one watcher for both gates (re-arming --watch to wait on CI just
#              re-exited immediately; three redundant re-arms, FE wave 2026-08-01).
#
# The step-4 gate, executable. Answers ONE question: are both gates satisfied on
# the CURRENT head — CI green, and a Codex verdict dispositioned?
#
# Every rule this encodes was learned by getting it wrong; see review.md ("Reading the
# verdict", "The loop") and deploy.md (watcher rules). Re-implementing it by hand each round is
# how those bugs came back, so call this instead of writing a new watcher.
#
#   READY requires BOTH, and they fail in opposite directions:
#     * unresolved threads == 0, AND
#     * a Codex verdict whose commit is the current head.
#   Neither alone is readiness. A clean pass does NOT retract an open finding on
#   the same head — duplicate passes on one commit can disagree (BE#308).
#
#   NON-DRAFT PRs additionally require POST-REQUEST activity: the newest Codex
#   answer (review/comment on this head, thread, or a 👍 on the request) must
#   postdate the latest `@codex review`. This encodes the ready-flip rule
#   (merge.md, "The flip"): the flip's auto-round does not fire after a fresh
#   same-head verdict (4/4 PRs, 2026-08-22), so the post-flip round is forced
#   by an explicit request — and a head-only verdict check cannot see whether
#   that request was ever answered. Drafts keep head-only semantics (the
#   iterate loop's verdicts are invalidated by pushes, not by requests).
#   Trade-off, accepted: a redundant re-request on an already-clean non-draft
#   head now holds the gate red until Codex answers it — that matches the
#   "pending re-review is in-flight, not ready" rule; don't re-request idly.
#
# Exit: 0 = READY   1 = NOT READY (reason printed)   2 = BROKEN (trust nothing)

set -uo pipefail

PR=""; REPO=""; WATCH=0; QUIET=0; WAITCI=0; SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  REPO="$2"; shift 2 ;;
    --watch) WATCH=1; shift ;;
    --wait-ci) WAITCI=1; shift ;;
    --since) SINCE="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) PR="$1"; shift ;;
  esac
done
[ -n "$PR" ] || { echo "usage: pr-gates.sh <pr> [--repo owner/name] [--watch]"; exit 2; }

if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
  [ -n "$REPO" ] || { echo "BROKEN: no --repo and cwd is not a gh repo"; exit 2; }
fi
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"

say() { [ "$QUIET" = 1 ] || echo "$@"; }

# ---------------------------------------------------------------------------
# One raw query per phase/poll, validated before any local filters. Malformed
# JSON, API errors and missing evidence fail BROKEN; an empty filter result
# must never conceal a failed API read (BE#308).
# Window sizes (BE#401, 2026-08-05): EVERY thread reply creates a review
# object, so a long disposition loop inflates these collections fast (35
# reviews by round 8). GraphQL last:N reads the NEWEST end — the REST
# pulls/N/reviews default (first 30, ASCENDING) went permanently blind the
# moment the count crossed a page, which is why hand-rolled REST watchers are
# banned (review.md, "Reading the verdict"). Read the newest page, then page backwards
# until the complete history is buffered; unresolved findings never age out of the gate.
# ---------------------------------------------------------------------------
# One buffered snapshot per phase/poll; large histories page backwards before any filters.
refresh_snapshot() {
  GQ_SNAPSHOT=$(python3 - "$OWNER" "$NAME" "$PR" <<'PY'
import json
import re
import subprocess
import sys
import time

owner, name, number = sys.argv[1:]
fields = {
    "reviews": "id commit{oid} submittedAt author{login} body comments(first:50){totalCount nodes{body}}",
    "comments": "id author{login} authorAssociation createdAt body",
    "reviewThreads": "id isResolved comments(first:1){nodes{author{login} originalCommit{oid} createdAt body path}}",
}
sizes = {"reviews": 50, "comments": 50, "reviewThreads": 100}
metadata = "headRefOid headRefName state isDraft"
deadline = time.monotonic() + 120


def query(selection):
    return "{repository(owner:" + json.dumps(owner) + ",name:" + json.dumps(name) + "){pullRequest(number:" + str(int(number)) + "){" + metadata + " " + selection + "}}}"


def connection(key, cursor=None):
    before = ",before:" + json.dumps(cursor) if cursor is not None else ""
    return key + "(last:" + str(sizes[key]) + before + "){totalCount pageInfo{hasPreviousPage startCursor} nodes{" + fields[key] + "}}"


def read(selection):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError("snapshot pagination exceeded its 120s budget")
    result = subprocess.run(["gh", "api", "graphql", "-f", "query=" + query(selection)],
                            capture_output=True, text=True, timeout=min(60, remaining))
    if result.returncode:
        raise ValueError("API read failed (auth, network or rate limit)")
    response = json.loads(result.stdout)
    if not isinstance(response, dict) or response.get("errors"):
        raise ValueError("API errors or malformed response")
    pr = response.get("data", {}).get("repository", {}).get("pullRequest")
    if not isinstance(pr, dict) or not isinstance(pr.get("headRefOid"), str) or not re.fullmatch(r"[0-9a-fA-F]{40}", pr["headRefOid"]) or not isinstance(pr.get("isDraft"), bool):
        raise ValueError("missing PR data or invalid head")
    return pr


def count(value):
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError("invalid connection count")
    return value


def page(pr, key):
    value = pr.get(key)
    if not isinstance(value, dict) or not isinstance(value.get("nodes"), list) or not all(isinstance(node, dict) for node in value["nodes"]):
        raise ValueError("malformed " + key + " page")
    count(value.get("totalCount"))
    if len(value["nodes"]) > value["totalCount"]:
        raise ValueError("page exceeds its connection count")
    return value


try:
    snapshot = read(" ".join(connection(key) for key in fields))
    identity = tuple(snapshot.get(key) for key in ("headRefOid", "headRefName", "state", "isDraft"))
    totals = {}
    paginated = False
    for key in fields:
        current = page(snapshot, key)
        total = totals[key] = current["totalCount"]
        nodes = list(current["nodes"])
        if any("id" in node for node in nodes):
            ids = [node.get("id") for node in nodes]
            if any(not isinstance(item, str) or not item for item in ids) or len(set(ids)) != len(ids):
                raise ValueError("missing/duplicate initial node identity")
        cursors = set()
        pages = 1
        while len(nodes) < total:
            paginated = True
            info = current.get("pageInfo")
            if not isinstance(info, dict) or info.get("hasPreviousPage") is not True or not isinstance(info.get("startCursor"), str) or not info["startCursor"]:
                raise ValueError("truncated " + key + " history: missing previous-page cursor")
            cursor = info["startCursor"]
            if cursor in cursors or pages >= 100:
                raise ValueError("repeated cursor or excessive " + key + " pagination")
            cursors.add(cursor)
            older_pr = read(connection(key, cursor))
            if tuple(older_pr.get(field) for field in ("headRefOid", "headRefName", "state", "isDraft")) != identity:
                raise ValueError("PR head/state changed during pagination")
            current = page(older_pr, key)
            older_info = current.get("pageInfo")
            if not isinstance(older_info, dict) or not isinstance(older_info.get("hasPreviousPage"), bool) or not isinstance(older_info.get("startCursor"), str) or not older_info["startCursor"] or older_info["startCursor"] in cursors:
                raise ValueError("missing or repeated previous-page boundary")
            if current["totalCount"] != total or not current["nodes"]:
                raise ValueError("connection count changed or empty previous page")
            nodes = current["nodes"] + nodes
            ids = [node.get("id") for node in nodes]
            if any(not isinstance(item, str) or not item for item in ids) or len(set(ids)) != len(ids) or len(nodes) > total:
                raise ValueError("missing/duplicate node identity or inconsistent page count")
            pages += 1
        info = current.get("pageInfo")
        # Complete small legacy fixtures omit pageInfo; real API requests always ask for it.
        if info is not None and (not isinstance(info, dict) or info.get("hasPreviousPage") is not False):
            raise ValueError("inconsistent final pagination boundary")
        snapshot[key]["nodes"] = nodes
        snapshot[key]["totalCount"] = total
    if paginated:
        final = read(" ".join(key + "(last:1){totalCount}" for key in fields))
        if tuple(final.get(field) for field in ("headRefOid", "headRefName", "state", "isDraft")) != identity or any(count(final.get(key, {}).get("totalCount")) != totals[key] for key in fields):
            raise ValueError("PR head/state or connection count changed before snapshot completion")
    print(json.dumps({"data": {"repository": {"pullRequest": snapshot}}}))
except (ValueError, TypeError, AttributeError, KeyError, subprocess.SubprocessError, OSError) as error:
    print("BROKEN: review evidence unreadable (PR review snapshot): " + str(error))
    sys.exit(2)
PY
  ) || { echo "$GQ_SNAPSHOT"; return 2; }
}
gq() { printf '%s\n' "$GQ_SNAPSHOT" | jq -r "$1"; }
refresh_snapshot || exit 2

# Self-test the status source FIRST and fail LOUDLY. A watcher whose calls all
# error looks identical to a quiet one and loops forever. (deploy.md)
HEAD="$(gq '.data.repository.pullRequest.headRefOid')"
case "$HEAD" in
  ????????????????????????????????????????) : ;;
  *) echo "BROKEN: cannot read PR $PR in $REPO (auth? repo? number?) — got: '$HEAD'"; exit 2 ;;
esac

# The last `@codex review` request bounds "is this verdict for the current ask".
# Author-exclude the bot: a request can only come from us, but Codex's own
# verdict comment quotes "@codex review" in its help text (FE PR#250,
# 2026-08-01) — unfiltered, the boundary jumps to the verdict's own timestamp
# and every time-filtered read (c2's time path, c3, the ack target) sits past it.
req_ts() {
  local c f
  c="$(gq '[.data.repository.pullRequest.comments.nodes[]
      |select((.author.login // "")|IN("chatgpt-codex-connector","chatgpt-codex-connector[bot]")|not)
      |select((.authorAssociation // "")|IN("OWNER","MEMBER","COLLABORATOR"))
      |select(.body|test("@codex review";"i"))|.createdAt]|last // ""')" || return 2
  # The ready-for-review flip is a request too: it triggers its own Codex
  # round, whose verdict can land AFTER the previous request's answer — a
  # head-only read then says READY on the pre-flip verdict (BE PR#773,
  # 2026-09-13: flip 19:44:25, READY read at 19:50 on the 19:42 verdict, the
  # flip round landed at 19:54 with 3 findings). The later of the two bounds
  # the current ask.
  f="$(gh api "repos/$REPO/issues/$PR/timeline" --paginate --slurp 2>/dev/null | jq -r '[.[][]|select(.event=="ready_for_review")|.created_at]|max // ""' 2>/dev/null)" || return 2
  if [ -n "$f" ] && [[ "$f" > "$c" ]]; then echo "$f"; else echo "$c"; fi
}

report() {
  local head="$1" reqts="$2" windows
  # The buffered reader must cover every node; local filters never trust partial history.
  windows="$(gq '.data.repository.pullRequest | [.reviews, .comments, .reviewThreads] | all(.[]; (.totalCount|type)=="number" and .totalCount==(.nodes|length))')"
  if [ "$windows" != true ]; then
    echo "BROKEN: review evidence is truncated or unreadable — cannot gate this PR from bounded tails"
    exit 2
  fi

  # Only the verified connector account (GraphQL and REST login forms) can supply review evidence.
  # --- CHANNEL 1: formal review BY CODEX on this exact head --------------
  # Author filter is load-bearing: OUR OWN thread replies come back as reviews
  # on the head with an EMPTY body, and matched a commit-oid-only filter — the
  # round appeared to close itself. Body is not a discriminator either; Codex
  # files findings with an empty body, carrying them in inline comments.
  local c1 c1n
  c1="$(gq "[.data.repository.pullRequest.reviews.nodes[]
        |select(.commit.oid==\"$head\")
        |select(.author.login|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))]|last // empty")"
  c1n="$(gq "[.data.repository.pullRequest.reviews.nodes[]
        |select(.commit.oid==\"$head\")
        |select(.author.login|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))]|length")"

  # --- CHANNEL 2: clean-pass issue comment for THIS head -----------------
  # HEAD-ONLY match. History of this filter, because both prior shapes bit us:
  # time-only went verdict-blind when our own no-👀 re-request moved reqts past
  # a landed clean pass (PR#324, 2026-08-01); the time-OR-head repair then
  # produced the OPPOSITE failure — a verdict for an OLDER commit arriving
  # after the newest request read as READY for a head nothing had reviewed
  # (PR#519 head 0a7c606, 2026-08-18). Codex embeds "Reviewed commit: <sha>"
  # in every comment verdict, so naming the CURRENT head is the one
  # discriminator that is both necessary and sufficient — no time arm.
  local c2 head10
  head10="${head:0:10}"  # Codex renders a 10-char short sha in "Reviewed commit:"
  # A failed round is not a verdict: Codex's error reply quotes the FULL head sha ("Provided git ref
  # <sha> does not exist") and matched as a clean pass — READY on a round that never ran (FE PR#566, 2026-09-29).
  local noerr='select(.body|test("Something went wrong";"i")|not)'   # single quotes: no \" here, it reaches jq literally
  c2="$(gq "[.data.repository.pullRequest.comments.nodes[]
        |select(.author.login|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))
        |$noerr
        |select(.body|contains(\"$head10\"))
        |.body]|last // \"\"")"
  # A review can also arrive as ONE issue comment that CARRIES findings ("### 💡 Codex Review", a P-badge + a blob link
  # per finding, no review object, no thread): it names the head, so it matched above as a clean pass and READY was
  # printed over six P2s (skills PR#60 R6, 2026-10-02). Every finding in EVERY Codex comment on this head stays open
  # until a LATER comment of ours carries a line starting `codex-comment-findings: <head7> dispositioned` — a later
  # clean or shorter Codex comment retracts nothing. The marker counts only from a repo OWNER / MEMBER / COLLABORATOR
  # (two fork repos are public: anyone can comment there). ONE read yields "<open> <found>"; anything else is unreadable
  # and fails closed (Codex, PR#60 R7, R9).
  local cf
  cf="$(gq "[.data.repository.pullRequest.comments.nodes[]] as \$c
        | ([\$c[]|select((.author.login // \"\")|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\")|not)
            |select((.authorAssociation // \"\")|test(\"^(OWNER|MEMBER|COLLABORATOR)$\"))
            |select(.body|test(\"(^|\\n)codex-comment-findings: ${head:0:7} dispositioned\"))|.createdAt]|last // \"\") as \$m
        | [\$c[]|select((.author.login // \"\")|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))|$noerr|select(.body|contains(\"$head10\"))
            |{t: .createdAt, n: ([.body|scan(\"badge/P[0-9]\")]|length)}] as \$f
        | \"\\([\$f[]|select(.t >= \$m)|.n]|add // 0) \\([\$f[]|.n]|add // 0)\"")"
  if [[ "$cf" =~ ^[0-9]+\ [0-9]+$ ]]; then CF_OPEN=${cf% *}; CF_FOUND=${cf#* }; else CF_OPEN=unreadable; CF_FOUND=unreadable; fi
  CODEX_FAILED="$(gq "[.data.repository.pullRequest.comments.nodes[]
        |select(.author.login|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))
        |select(.body|test(\"Something went wrong\";\"i\"))
        |select(.body|contains(\"$head10\"))
        |select(.createdAt > \"$reqts\")]|length")"

  # --- CHANNEL 3: threads-only round (no review body, no comment) --------
  local c3 c3head
  c3head="$(gq "[.data.repository.pullRequest.reviewThreads.nodes[]
        |select(.comments.nodes[0].author.login|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))
        |select(.comments.nodes[0].originalCommit.oid==\"$head\")]|length")"
  c3="$(gq "[.data.repository.pullRequest.reviewThreads.nodes[]
        |select(.comments.nodes[0].author.login|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))
        |select(.comments.nodes[0].originalCommit.oid==\"$head\")
        |select(.comments.nodes[0].createdAt > \"$reqts\")]|length")"

  local unres
  unres="$(gq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length')"

  # --- POST-REQUEST activity (gates non-draft PRs only) ------------------
  # Head-only channels cannot see whether the LATEST request was answered:
  # a pre-flip verdict on an unchanged head satisfied them while the required
  # post-flip round sat unanswered, and the old "(since $reqts)" display made
  # that read as answered (2 false READYs, 2026-08-22). Same head discipline
  # as c1/c2 (a post-request verdict for an OLDER commit must not count —
  # PR#519 shape); the 👍 arm is Codex's documented no-findings ack.
  local pq1 pq2 reqid thumbs
  pq1="$(gq "[.data.repository.pullRequest.reviews.nodes[]
        |select(.commit.oid==\"$head\")
        |select(.author.login|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))
        |select(.submittedAt > \"$reqts\")]|length")"
  pq2="$(gq "[.data.repository.pullRequest.comments.nodes[]
        |select(.author.login|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))
        |$noerr
        |select(.body|contains(\"$head10\"))
        |select(.createdAt > \"$reqts\")]|length")"
  reqid="$(gh api "repos/$REPO/issues/$PR/comments" --paginate \
          --jq "[.[]|select((.user.login // \"\")|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\")|not)|select((.author_association // \"\")|IN(\"OWNER\",\"MEMBER\",\"COLLABORATOR\"))|select(.body|test(\"@codex review\";\"i\"))]|last|.id // empty" 2>/dev/null | tail -1)" || { echo "BROKEN: cannot read review request comments"; exit 2; }
  thumbs=0
  if [ -n "$reqid" ]; then
    thumbs="$(gh api "repos/$REPO/issues/comments/$reqid/reactions" --paginate --slurp 2>/dev/null | jq -r --arg reqts "$reqts" 'if type != "array" or any(.[]; type != "array") then error("invalid reaction pages") else . end | [.[].[]|select(.content=="+1")|select((.user.login // "")|IN("chatgpt-codex-connector","chatgpt-codex-connector[bot]"))|select(.created_at > $reqts)]|length' 2>/dev/null)" || { echo "BROKEN: cannot read request-comment reactions"; exit 2; }
    [[ "$thumbs" =~ ^[0-9]+$ ]] || { echo "BROKEN: invalid request-comment reactions"; exit 2; }
  fi
  # Codex's 👍 lands on the PR ISSUE, never on the request comment (verified
  # FE PR#524 + PR#528, 2026-09-14: zero codex reactions on four request
  # comments, a +1 on each PR) — the comment arm above never fires. A clean
  # round on an unchanged head posts NO comment, so this 👍 is its only
  # answer (PR#528: 👍 80 s after `gh pr ready`, --watch blocked 20+ min on
  # "predates the latest request"). Codex re-creates the 👍 per round, so
  # created_at > reqts is the round-after-request test.
  local prthumbs
  prthumbs="$(gh api "repos/$REPO/issues/$PR/reactions" --paginate --slurp 2>/dev/null | jq -r "if type != \"array\" or any(.[]; type != \"array\") then error(\"invalid reaction pages\") else . end | [.[].[]|select(.content==\"+1\")|select((.user.login // \"\")|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\"))|select(.created_at > \"$reqts\")]|length" 2>/dev/null)" || { echo "BROKEN: cannot read PR reactions"; exit 2; }
  [[ "$prthumbs" =~ ^[0-9]+$ ]] || { echo "BROKEN: invalid PR reactions"; exit 2; }
  POSTREQ=0
  [ "${pq1:-0}" -gt 0 ] && POSTREQ=1
  [ "${pq2:-0}" -gt 0 ] && POSTREQ=1
  [ "${c3:-0}" -gt 0 ] && POSTREQ=1
  [ "${thumbs:-0}" -gt 0 ] && POSTREQ=1
  [ "${prthumbs:-0}" -gt 0 ] && POSTREQ=1

  IS_DRAFT="$(gq '.data.repository.pullRequest.isDraft')"

  say "PR $REPO#$PR  head=$head$([ "$IS_DRAFT" = "true" ] && echo ' (draft)')"
  say "  unresolved threads : $unres"
  say "  ch1 codex review   : ${c1n:-0} on head"
  say "  ch2 codex comment  : $([ -n "$c2" ] && echo yes || echo no) (head-match, time-blind)$([ "${CF_FOUND:-0}" != 0 ] && echo " — findings carried in Codex comments on this head: $CF_FOUND, still open: $CF_OPEN")"
  say "  ch3 codex threads  : ${c3head:-0} on head; ${c3:-0} since request"
  say "  post-request       : $([ "$POSTREQ" = 1 ] && echo yes || echo no) (answer after latest request $reqts; gates non-draft$([ "${prthumbs:-0}" -gt 0 ] && echo '; 👍 on the PR after the request'))"

  # --- CI: NAMED checks on the head, at JOB level, two agreeing reads ----
  # The run summary FLAPS (deploy.md); jobs stayed truthful. And absent
  # CI is not green — a head with no run at all fails this gate.
  local runs a b sel
  sel="select(.name!=\"Vercel\")|select(any(.pull_requests[]?; .number == $PR))"
  [ -n "$SINCE" ] && sel="$sel|select(.created_at >= \"$SINCE\")"  # runs from BEFORE the triggering action do not count; >= keeps a run minted in the same second as `t` (PR #23 R2)
  read_runs() {
    local data rows path run_id status conclusion proof rc
    data=$(gh api "repos/$REPO/actions/runs?head_sha=$head&event=pull_request&per_page=100" --paginate --slurp 2>/dev/null) || return 2
    rows=$(printf '%s\n' "$data" | jq -r "[.[].workflow_runs[]|$sel]|group_by(.workflow_id)|map(sort_by(.created_at,.id)|last)|.[]|[(.path|split(\"@\")[0]),(.id|tostring),.status,(.conclusion // \"\")]|@tsv" 2>/dev/null) || return 2
    while IFS=$'\t' read -r path run_id status conclusion; do
      [ -n "$path" ] || continue
      if [ "$status" = completed ] && [ "$conclusion" = success ] && [ "$IS_DRAFT" != true ]; then
        proof=$(python3 "$(dirname "$0")/ci-jobs.py" "$REPO" "$run_id" "$path" "$head"); rc=$?
        case $rc in
          0) ;;
          1) conclusion=required-jobs-not-successful; echo "CI job proof: $path: $proof" >&2;;
          *) echo "BROKEN: cannot verify $path jobs: $proof" >&2; return 2;;
        esac
      fi
      printf '%s=%s:%s\n' "$path" "$status" "$conclusion"
    done <<< "$rows"
  }

  runs="$(read_runs)" || { echo "BROKEN: cannot read or verify current-head workflow jobs"; exit 2; }
  sleep 5
  b="$(read_runs)" || { echo "BROKEN: cannot read or verify current-head workflow jobs"; exit 2; }
  # An EMPTY listing flaps too: ci-wait's final gate read `<none>` seconds after enumerating
  # both runs green on the same head (clab PR#232, 2026-09-29). Exactly one empty read = a
  # transient — a third read after 10 s decides; both empty = truly absent (not green).
  # (grouped: bash's && and || share precedence — ungrouped, the first-empty case never retried; PR #37 R1)
  if { [ -z "$runs" ] && [ -n "$b" ]; } || { [ -n "$runs" ] && [ -z "$b" ]; }; then
    sleep 10; runs="$(read_runs)" || { echo "BROKEN: cannot read or verify current-head workflow jobs"; exit 2; }; b="$runs"
  fi
  a="$runs"
  say "  CI on head         : ${a:-<none>}"

  CI_OK=0; CI_NA=0
  local green_pattern="=completed:success$"
  [ "$IS_DRAFT" = true ] && green_pattern="=completed:(success|skipped)$"
  if [ -z "$a" ]; then
    # Absent CI is not green — unless the repo has NO workflows at all (netpilot-skills): then the
    # CI half is the repo's local check recorded in the PR body (merge.md, "A repo with NO CI
    # workflows") and this gate reports N/A instead of holding forever (PR #21, 2026-09-28).
    local nwf att
    nwf="$(gh api "repos/$REPO/actions/workflows" --jq '.total_count' 2>/dev/null)"
    if [ "${nwf:-x}" = "0" ]; then
      # The CI half is the repo's local check, ATTESTED for this exact head in the PR body as a line
      # `local-check: <head-sha> …` (merge.md). No attestation, or one for an older head = not green:
      # a verdict alone must never merge a script nobody parsed (PR #23 R1 P1, 2026-09-28).
      # anchored + affirmative: the line must START with `local-check: <head7>` — a checklist item
      # (`- [ ] local-check: …`) or a sentence about the check must not count (PR #23 post-flip P1)
      att="$(gh pr view "$PR" -R "$REPO" --json body --jq '.body' 2>/dev/null | grep -cE "^[[:space:]]*local-check: ${head:0:7}([^[:alnum:]]|$)")"
      if [ "${att:-0}" -gt 0 ]; then
        CI_OK=1; CI_NA=1; say "  CI                 : N/A — no workflows; local-check attestation for ${head:0:7} found in the PR body"
      else
        CI_REASON="repo has no workflows and the PR body carries no \`local-check: ${head:0:7}\` attestation (merge.md)"
      fi
    else
      CI_REASON="no CI run on this head (absent is NOT green)"
    fi
  elif [ "$a" != "$b" ]; then
    CI_REASON="CI state flapped between two reads — not settled"
  elif echo "$a" | grep -qvE "$green_pattern"; then
    CI_REASON="CI not green: $(echo "$a" | grep -vE "$green_pattern" | tr '\n' ' ')"
  elif [ "$IS_DRAFT" != "true" ] && ! echo "$a" | grep -qvE ":skipped$"; then
    # every run on this head is a draft-era skipped run: the flip minted no real run (merge.md, CI never ran)
    CI_REASON="only skipped (draft-era) runs on this head — no real CI run yet (merge.md, CI never ran)"
  else
    # A workflow that minted NO run on this head (event miss, cancelled by the concurrency group) is
    # invisible in the head's run list, so the required set comes from this PR's own run history:
    # every workflow required-workflows.sh names must have a run on the current head (PR #23 R4).
    local expected missing="" have expected_lines touched="" wfbroken=0
    # Required set includes active PR-associated history and definitely matching unseen PR declarations.
    # Unsupported declaration syntax fails closed. Added/removed/renamed workflow paths remain
    # excluded here under the existing guarded-workflow-change policy; modified workflows must run.
    # a MODIFIED workflow keeps its historical entry (it must still run); only added/removed/renamed paths leave (#27 R4 P1)
    if ! touched="$(gh api "repos/$REPO/pulls/$PR/files" --paginate --jq '.[]|select(.filename|startswith(".github/workflows/"))|select(.status!="modified")|.filename, (.previous_filename // empty)' 2>/dev/null)"; then wfbroken=1; fi
    if ! expected_lines="$("$(dirname "$0")/required-workflows.sh" "$REPO" "$PR")"; then wfbroken=1; fi
    expected="$(printf '%s\n' "$expected_lines" | while IFS=$'\t' read -r p rest; do [ -n "$p" ] || continue; printf '%s\n' "$touched" | grep -qxF -- "$p" || printf '%s\n' "$p"; done)"
    if [ "$wfbroken" = 1 ]; then
      CI_REASON="cannot read this PR's file list or its required-workflow set (required-workflows.sh) — trust nothing"
    else
      have="$(printf '%s\n' "$a" | sed 's/=.*$//')"   # exact workflow-path field, one per line
      while IFS= read -r w; do
        [ -n "$w" ] || continue
        printf '%s\n' "$have" | grep -qxF -- "$w" || missing="$missing [$w]"   # exact path match; duplicate display names cannot satisfy a missing workflow
      done <<< "$expected"
      if [ -n "$missing" ]; then
        CI_REASON="required workflow(s) with no run on this head:$missing — event miss or cancelled run (merge.md, CI never ran)"
      else
        CI_OK=1
      fi
    fi
  fi

  VERDICT_ON_HEAD=0
  [ "${c1n:-0}" -gt 0 ] && VERDICT_ON_HEAD=1
  [ -n "$c2" ] && VERDICT_ON_HEAD=1
  [ "${c3head:-0}" -gt 0 ] && VERDICT_ON_HEAD=1
  UNRES="$unres"
}

escalate_if_no_ack() {
  # The 5-min no-👀 rule is the WATCHER's job, not an observation (deploy.md).
  # Same author-exclusion as req_ts: the ack target must be OUR request — a
  # Codex verdict quoting the phrase has no 👀 and would trigger a duplicate
  # (paid) re-request every escalation window.
  local reqts="$1" acks
  acks="$(gh api "repos/$REPO/issues/$PR/comments" --paginate \
          --jq "[.[]|select((.user.login // \"\")|IN(\"chatgpt-codex-connector\",\"chatgpt-codex-connector[bot]\")|not)|select((.author_association // \"\")|IN(\"OWNER\",\"MEMBER\",\"COLLABORATOR\"))|select(.body|test(\"@codex review\";\"i\"))]|last|.id // empty" 2>/dev/null | tail -1)"
  [ -n "$acks" ] || return 0
  local eyes
  eyes="$(gh api "repos/$REPO/issues/comments/$acks/reactions" --paginate --slurp 2>/dev/null | jq -r '[.[].[]|select(.content=="eyes")|select((.user.login // "")|IN("chatgpt-codex-connector","chatgpt-codex-connector[bot]"))]|length' 2>/dev/null)" || { echo "BROKEN: cannot read request reactions — trust nothing"; exit 2; }
  [[ "${eyes}" =~ ^[0-9]+$ ]] || { echo "BROKEN: unreadable request reactions — trust nothing"; exit 2; }
  if [ "${eyes:-0}" = "0" ]; then
    echo "  no 👀 on the request after 5min — RE-REQUESTING (review.md, The loop)"
    if env -u GH_TOKEN -u GITHUB_TOKEN gh pr comment "$PR" -R "$REPO" --body "@codex review" >/dev/null 2>&1 \
      || gh pr comment "$PR" -R "$REPO" --body "@codex review" >/dev/null 2>&1; then
      # the replacement request must be OBSERVABLE before it bounds later reads, else a verdict that landed in the
      # window could count as post-request activity on the next poll (#27 R5 P1) — same check as the post-flip path
      PF_REREQ=1; PF_T=$(date +%s)   # one retry total; an unanswered replacement holds after 15 min
      local old_ts="$REQTS" i
      for i in 1 2 3 4 5 6; do refresh_snapshot || exit 2; REQTS="$(req_ts)"; [ -n "$REQTS" ] && [[ "$REQTS" > "$old_ts" ]] && break; sleep 10; done
      if ! { [ -n "$REQTS" ] && [[ "$REQTS" > "$old_ts" ]]; }; then
        echo "BROKEN: the re-request was posted but is not visible after 60 s — trust nothing"; [ "$WAITCI" = 1 ] && echo "ci-wait: FINAL BROKEN"; exit 2
      fi
    else
      echo "BROKEN: could not post the no-ack re-request (auth? rate limit?) — trust nothing"; [ "$WAITCI" = 1 ] && echo "ci-wait: FINAL BROKEN"; exit 2
    fi
  fi
}

decide() {
  local fresh=1
  [ "$IS_DRAFT" != "true" ] && [ "$POSTREQ" != 1 ] && fresh=0
  if [ "$VERDICT_ON_HEAD" = 1 ] && [ "$UNRES" = 0 ] && [ "${CF_OPEN:-0}" = 0 ] && [ "$CI_OK" = 1 ] && [ "$fresh" = 1 ]; then
    say "READY — verdict on head, 0 unresolved, CI $([ "${CI_NA:-0}" = 1 ] && echo 'N/A (no workflows; local-check attested for this head)' || echo green)$([ "$IS_DRAFT" != "true" ] && echo ', latest request answered')."
    say "NOTE: readiness is not zero findings. Review the verdict's SUBSTANCE;"
    say "      a clean pass never retracts a finding you have not answered."
    return 0
  fi
  local why=""
  [ "$VERDICT_ON_HEAD" = 0 ] && why="$why; no Codex verdict on the current head"
  [ "${CODEX_FAILED:-0}" -gt 0 ] && why="$why; Codex round FAILED after the latest request (\"Something went wrong\") — re-request; a reviewer outage is never risk-accepted"
  [ "$VERDICT_ON_HEAD" = 1 ] && [ "$fresh" = 0 ] && why="$why; verdict predates the latest @codex request — the post-flip/pending round is unanswered (merge.md, The flip)"
  [ "$UNRES" != 0 ] && why="$why; $UNRES unresolved thread(s) — disposition each ONE BY ONE"
  [ "${CF_OPEN:-0}" = unreadable ] && why="$why; the read of findings carried in Codex comments FAILED — trust nothing, re-run"
  [ "${CF_OPEN:-0}" != 0 ] && [ "${CF_OPEN:-0}" != unreadable ] && why="$why; Codex's verdict on this head is an ISSUE COMMENT carrying $CF_OPEN finding(s) (no threads to resolve) — disposition each: a fix push, or a PR comment with a line starting \`codex-comment-findings: ${HEAD:0:7} dispositioned\` and the per-finding dispositions"
  [ "$CI_OK" = 0 ] && why="$why; ${CI_REASON:-CI not green}"
  say "NOT READY${why}"
  return 1
}

if ! REQTS="$(req_ts)"; then
  echo "BROKEN: cannot read latest review request or ready-for-review timeline"
  exit 2
fi
[ -n "$REQTS" ] || { echo "BROKEN: missing review request boundary — request @codex review before gating"; exit 2; }

if [ "$WATCH" = 0 ]; then
  report "$HEAD" "$REQTS"; decide; exit $?
fi

# --- watch mode ------------------------------------------------------------
START=$(date +%s); EMPTY=0; PF_REREQ=0; PF_T=0
say "watching $REPO#$PR head=$HEAD (request at $REQTS)"
while :; do
  refresh_snapshot || exit 2
  CUR="$(gq '.data.repository.pullRequest.headRefOid')"
  # Distinguish "no value" from "a different value". An empty read is an API
  # error; treating it as a change is how a watcher exits 0 having seen nothing
  # at all (BE#308). But "keep waiting" forever is the OTHER failure — expired
  # auth reads exactly like a quiet PR — so empty reads are counted and fatal.
  if [ -z "$CUR" ]; then
    EMPTY=$(( EMPTY + 1 ))
    if [ "$EMPTY" -ge 5 ]; then
      echo "BROKEN: 5 consecutive unreadable polls (auth expired? network?)"
      gh auth status 2>&1 | head -5
      exit 2
    fi
    sleep 60; continue
  fi
  EMPTY=0
  if [ "$CUR" != "$HEAD" ]; then
    echo "HEAD MOVED $HEAD -> $CUR (someone pushed; restart the watch)"; exit 2
  fi
  if ! latest_req="$(req_ts)"; then
    echo "BROKEN: cannot refresh latest review request boundary"; exit 2
  fi
  [ -n "$latest_req" ] || { echo "BROKEN: missing review request boundary during watch"; exit 2; }
  if [[ "$latest_req" > "$REQTS" ]]; then
    REQTS="$latest_req"
    START=$(date +%s); PF_REREQ=0; PF_T=0
    say "new review request observed at $REQTS; reset acknowledgement timers"
  fi
  poll_quiet=$QUIET; QUIET=1
  report "$HEAD" "$REQTS"
  QUIET=$poll_quiet
  # Non-draft: keep watching until the LATEST request is answered — exiting on
  # a stale on-head verdict is exactly the false-READY this lane exists to
  # prevent (2026-08-22).
  if [ "$VERDICT_ON_HEAD" = 1 ] && { [ "$IS_DRAFT" = "true" ] || [ "$POSTREQ" = 1 ]; }; then
    QUIET=0; report "$HEAD" "$REQTS"; decide; rc=$?
    if [ "$WAITCI" = 1 ] && [ "$IS_DRAFT" = "true" ]; then
      echo "draft PR: CI is draft-gated on these repos — --wait-ci applies after the ready flip (merge.md, The flip)"
      echo "ci-wait: FINAL NOT READY (draft)"; rc=1
    elif [ "$WAITCI" = 1 ] && [ "$rc" = 1 ] && [ "$UNRES" = 0 ] && [ "$CI_OK" = 0 ] && [ "${CI_NA:-0}" = 0 ]; then
      echo "verdict landed; CI pending — chaining into ci-wait.sh (read its FINAL line)"
      if [ -n "$SINCE" ]; then exec "$(dirname "$0")/ci-wait.sh" "$PR" --repo "$REPO" --since "$SINCE"
      else exec "$(dirname "$0")/ci-wait.sh" "$PR" --repo "$REPO"; fi
    elif [ "$WAITCI" = 1 ]; then
      # CI already settled when the verdict landed (common when review is slower than CI), or something
      # other than CI is missing: the caller reads ONE marker either way (merge.md) — PR #23 R2.
      case $rc in 0) echo "ci-wait: FINAL READY";; *) echo "ci-wait: FINAL NOT READY";; esac
    fi
    exit $rc
  fi
  # A failed round never flips VERDICT_ON_HEAD, so without this exit the watch reads it as silence.
  if [ "${CODEX_FAILED:-0}" -gt 0 ] && [ "$POSTREQ" != 1 ]; then
    echo "NOT READY; Codex round FAILED after the latest request (\"Something went wrong\") — re-request; never merge past it"
    [ "$WAITCI" = 1 ] && echo "ci-wait: FINAL NOT READY (codex round failed)"
    exit 1
  fi
  ELAPSED=$(( $(date +%s) - START ))
  # A loop counter is not a clock (deploy.md) — escalate on real elapsed.
  [ "$PF_REREQ" = 0 ] && [ "$ELAPSED" -ge 300 ] && [ $(( ELAPSED % 300 )) -lt 60 ] && escalate_if_no_ack "$REQTS"   # silent once the #22 re-request is out
  if [ "$PF_REREQ" = 1 ] && [ $(( $(date +%s) - PF_T )) -ge 900 ]; then
    echo "REVIEW UNANSWERED — two requests, no answer on head ${HEAD:0:10}: HOLD and report to Lin; never merge past an unanswered request (#22)"
    [ "$WAITCI" = 1 ] && echo "ci-wait: FINAL NOT READY (review unanswered)"
    exit 1
  fi
  # Lin's #22 ruling (2026-09-28): a NON-draft head that already carries a verdict, whose latest request
  # sits unanswered ~15 min, gets ONE automatic re-request; unanswered ~15 min later → report, never merge.
  if [ "$IS_DRAFT" != "true" ] && [ "$VERDICT_ON_HEAD" = 1 ] && [ "$POSTREQ" != 1 ]; then
    # only the PICKED-UP-but-unanswered shape (👀 on the latest request); no 👀 is escalate_if_no_ack's case
    PF_REQID="$(gh api "repos/$REPO/issues/$PR/comments" --paginate --jq '[.[]|select((.user.login // "")|IN("chatgpt-codex-connector","chatgpt-codex-connector[bot]")|not)|select((.author_association // "")|IN("OWNER","MEMBER","COLLABORATOR"))|select(.body|test("@codex review";"i"))]|last|.id // empty' 2>/dev/null | tail -1)"
    PF_EYES=0
    if [ -n "$PF_REQID" ]; then
      PF_EYES="$(gh api "repos/$REPO/issues/comments/$PF_REQID/reactions" --paginate --slurp 2>/dev/null | jq -r '[.[].[]|select(.content=="eyes")|select((.user.login // "")|IN("chatgpt-codex-connector","chatgpt-codex-connector[bot]"))]|length' 2>/dev/null)" || { echo "BROKEN: cannot read request reactions — trust nothing"; exit 2; }
      [[ "$PF_EYES" =~ ^[0-9]+$ ]] || { echo "BROKEN: unreadable request reactions — trust nothing"; exit 2; }
    fi
    PF_SINCE=$(( $(date +%s) - $(python3 -c "import sys,datetime;print(int(datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).timestamp()))" "$REQTS" 2>/dev/null || echo 0) ))
    if [ "${PF_EYES:-0}" -gt 0 ] && [ "$PF_REREQ" = 0 ] && [ "$PF_SINCE" -ge 900 ]; then
      echo "  post-flip request unanswered for 15 min on an already-verdicted head — ONE automatic re-request (#22)"
      if env -u GH_TOKEN -u GITHUB_TOKEN gh pr comment "$PR" -R "$REPO" --body "@codex review" >/dev/null 2>&1 \
        || gh pr comment "$PR" -R "$REPO" --body "@codex review" >/dev/null 2>&1; then
        # the new request must be OBSERVABLE before it bounds anything: an unchanged REQTS would let the old
        # draft-phase verdict satisfy the post-request test on the next poll (#27 R3 P1)
        PF_OLD="$REQTS"; PF_REREQ=1; PF_T=$(date +%s)
        for i in 1 2 3 4 5 6; do refresh_snapshot || exit 2; REQTS="$(req_ts)"; [ -n "$REQTS" ] && [[ "$REQTS" > "$PF_OLD" ]] && break; sleep 10; done
        if ! { [ -n "$REQTS" ] && [[ "$REQTS" > "$PF_OLD" ]]; }; then
          echo "BROKEN: the re-request was posted but is not visible after 60 s — trust nothing"; [ "$WAITCI" = 1 ] && echo "ci-wait: FINAL BROKEN"; exit 2
        fi
      else
        echo "BROKEN: could not post the post-flip re-request (auth? rate limit?) — trust nothing"; [ "$WAITCI" = 1 ] && echo "ci-wait: FINAL BROKEN"; exit 2
      fi
    fi
  fi
  if [ "$ELAPSED" -ge 4500 ]; then
    echo "TIMEOUT ${ELAPSED}s with no verdict in ANY channel — re-request (review.md, The loop)"
    [ "$WAITCI" = 1 ] && echo "ci-wait: FINAL NOT READY (no verdict before timeout)"
    exit 1
  fi
  sleep 60
done
