#!/usr/bin/env bash
# merge-slot.sh — ONE merge per repo at a time on this machine, held through that merge's deploy watch.
# Why: unblocked PRs run in parallel by default (Lin, 2026-10-01); two lanes passing merge.sh's base re-read in the
# same seconds would both merge, and a sibling would merge over a RED watch it never saw (Codex, skills PR#55).
# Every merge entry point takes it (dev-workflow/scripts/merge.sh, dependency-updates/scripts/merge.sh);
# postmerge.sh settles it. MACHINE-LOCAL by decision (PR#55): it serializes the lanes, sessions and passes of one
# machine. Two machines merging in one repo are not serialized by it — merge.sh steps 5–6 still catch a base that
# moves under a merge, nothing makes the second wait for the first's deploy watch.
#
#   acquire <o/r> <pr>            prints a token, exit 0 · prints why not, exit 1
#   peek    <o/r>                 prints the holder if held (dry runs); always exit 0
#   check   <o/r> <token>         exit 0 while the slot is still this token's — run RIGHT before `gh pr merge`: a run
#                                 paused past STALE_MIN was taken over and must not merge
#   sha     <o/r> <token> <sha>   records the merge sha (postmerge.sh matches on it)
#   release <o/r> <token> [merged] frees it if still this token's — callers release only on a PROVEN outcome, never on an
#                                 interrupt mid-merge: bare = not merged (an acknowledged holder comes back); `merged` =
#                                 merged in a repo with no deploy watch (an acknowledged hold is cleared with it)
#   settle  <o/r> <sha> <result>  postmerge.sh's exit: `clean` frees it; RED | BROKEN | REVIEW (+REVIEW when such lines
#                                 rode along) is written into the slot and it STAYS held — deploy.md: nothing else
#                                 merges until that result is read. `clean-skip` keeps a SENTRY-SKIPPED hold until Sentry is read or acknowledged
# A slot whose watch ended RED/BROKEN/REVIEW opens only to MERGE_SLOT_ACK=<holder pr>: that result was read and
# dispositioned (its fix or revert, or the next merge once every line is attributed) — and if that run ends without
# merging, the acknowledged holder is put back; once it MERGED the hold is gone (`sha` drops it where a watch follows,
# `release … merged` where none does: before that the holder came back after every merge in a no-deploy repo and each
# later merge needed the ACK again, clab PR#264–#267, 2026-10-02) — or to a clean postmerge.sh re-run that read every signal.
# Self-test (offline, temp claim dir): merge-slot-selftest.sh — run it after any edit here.
# An in-flight slot older than STALE_MIN=60 (longest watch: deploy 20 + main run 25 min) is a dead lane's: taken over
# (atomic rename) only when no merge sha was recorded AND its PR reads unmerged; one that merged needs the ACK too.
# Holder file: "<pr> <sha|pending> <token> <inflight|RED|BROKEN|REVIEW>".
set -uo pipefail
cmd=${1:-}; repo=${2:-}; STALE_MIN=60
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "usage: merge-slot.sh acquire|peek|check|sha|release|settle <owner/repo> …" >&2; exit 2; }
dir=${MERGE_CLAIM_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/netpilot-merge-claims}; slot="$dir/${repo/\//__}"; hf="$slot/holder"
rd() { hline=""; [ -f "$hf" ] && hline=$(cat "$hf" 2>/dev/null); read -r hpr hsha htok hstate <<< "$hline"; hpr=${hpr:-?}; hsha=${hsha:-?}; hstate=${hstate:-inflight}; }
# age = the holder file's mtime, else the dir's (a sibling between its mkdir and its write is FRESH, never stale)
age() { local a; a=$(python3 -c 'import os,sys,time; p=sys.argv[1]; h=os.path.join(p,"holder"); print(int((time.time()-os.path.getmtime(h if os.path.exists(h) else p))//60))' "${1:-$slot}" 2>/dev/null); [[ "$a" =~ ^[0-9]+$ ]] && echo "$a" || echo 0; }
take_over() { mv "$slot" "$slot.old.$$" 2>/dev/null && { rm -f "$slot.old.$$/holder" "$slot.old.$$/prev"; rmdir "$slot.old.$$/ack" 2>/dev/null; rmdir "$slot.old.$$" 2>/dev/null; }; }  # atomic: of two takers one wins
# a dead run that had taken the slot under an ACK: the acknowledged holder comes back instead of the slot opening
restore_prev() { [ -f "$slot/prev" ] || return 1; mv "$slot/prev" "$hf"; rd; why="PR#$hpr's deploy watch ended $hstate (merge ${hsha:0:10})"; }
case "$cmd" in
  peek) [ -d "$slot" ] && { rd; echo "merge slot for $repo is held by PR#$hpr ($hstate, $(age) min) — a real run waits for it"; }; exit 0;;
  acquire) pr=${3:?pr}
    if [ -d "$slot" ]; then rd; a=$(age); why=""
      if [ "$hstate" != inflight ]; then why="PR#$hpr's deploy watch ended $hstate (merge ${hsha:0:10})"
      elif [ "$a" -lt $STALE_MIN ]; then
        [ -d "$slot" ] && { echo "merge slot for $repo is held by PR#$hpr ($a min, merge ${hsha:0:10}) — wait for its deploy watch (postmerge.sh settles the slot), then re-run from --dry-run: main will have moved"; exit 1; }
      elif [ -z "$htok" ]; then echo "merge-slot: $repo slot is STALE and never got a token ($a min; no run could merge under it) — taking it over" >&2; restore_prev || take_over
      elif [ "$hsha" != pending ]; then why="PR#$hpr merged (${hsha:0:10}) $a min ago and its deploy watch never settled"
      else  # stale and no merge sha recorded: taken over only on PROOF that PR did not merge
        case "$(gh pr view "$hpr" -R "$repo" --json state --jq .state 2>/dev/null)" in
          OPEN|CLOSED) echo "merge-slot: $repo slot is STALE (PR#$hpr, $a min, not merged) — taking it over" >&2; restore_prev || take_over;;
          MERGED) why="PR#$hpr merged but its run recorded neither the merge sha nor a deploy watch";;
          *) echo "merge slot for $repo is stale (PR#$hpr, $a min) but that PR's state is unreadable — cannot prove it did not merge; re-run in a moment"; exit 1;;
        esac
      fi
      if [ -n "$why" ]; then
        if [ -n "${MERGE_SLOT_ACK:-}" ] && [ "$MERGE_SLOT_ACK" = "$hpr" ]; then
          # handed over IN PLACE under a one-instant mutex (`ack/`, atomic mkdir; one left by a crash is dropped after a
          # minute): the held record becomes `prev` only if it is still the record that was acknowledged, and the slot
          # directory never disappears — no sibling slips in without the ACK, of two acknowledged callers one wins. If this
          # run ends without merging, release puts `prev` back.
          [ -d "$slot/ack" ] && [ "$(age "$slot/ack")" -ge 1 ] && rmdir "$slot/ack" 2>/dev/null
          was=$hline; mkdir "$slot/ack" 2>/dev/null || { echo "merge slot for $repo is changing hands this instant — re-run from --dry-run"; exit 1; }
          rd; [ -n "$was" ] && [ "$hline" = "$was" ] || { rmdir "$slot/ack" 2>/dev/null; echo "merge slot for $repo changed hands this instant — re-run from --dry-run"; exit 1; }
          echo "merge-slot: acknowledged (MERGE_SLOT_ACK=$hpr): $why — taking the $repo slot" >&2
          tok="$pr.$$.$RANDOM$RANDOM"; mv "$hf" "$slot/prev"; echo "$pr pending $tok inflight" > "$hf"; rmdir "$slot/ack" 2>/dev/null; echo "$tok"; exit 0
        else echo "merge slot for $repo is held: $why — nothing else merges until that is dispositioned (deploy.md). A clean postmerge.sh for that merge frees it; its fix or revert, or the next merge once the result is read and every line attributed, runs with MERGE_SLOT_ACK=$hpr"; exit 1; fi
      fi
    fi
    mkdir -p "$dir" 2>/dev/null; mkdir "$slot" 2>/dev/null || { echo "merge slot for $repo was taken this instant by a sibling merge — wait for its deploy watch, then re-run from --dry-run"; exit 1; }
    tok="$pr.$$.$RANDOM$RANDOM"; echo "$pr pending $tok inflight" > "$hf"; echo "$tok";;
  check) rd; [ -n "$htok" ] && [ "$htok" = "${3:?token}" ];;
  sha) rd; [ -n "$htok" ] && [ "$htok" = "${3:?token}" ] && { echo "$hpr ${4:?sha} $htok inflight" > "$hf"; rm -f "$slot/prev"; };;
  release) rd; [ -n "$htok" ] && [ "$htok" = "${3:?token}" ] || exit 0
    if [ "${4:-}" = merged ]; then
      [ -f "$slot/prev" ] && echo "merge-slot: the acknowledged hold ($(cut -d' ' -f1,4 "$slot/prev")) is cleared by this merge — the $repo slot is free" >&2
      rm -f "$hf" "$slot/prev"; rmdir "$slot" 2>/dev/null
    elif [ -f "$slot/prev" ]; then mv "$slot/prev" "$hf"; echo "merge-slot: this run did not merge — the acknowledged holder is back in the $repo slot ($(cut -d' ' -f1,4 "$hf"))" >&2
    else rm -f "$hf"; rmdir "$slot" 2>/dev/null; fi; exit 0;;
  settle) sha=${3:?sha}; res=${4:?result}
    if [ ! -d "$slot" ]; then
      # a LATE re-run (the dependency ride-out) that ends non-clean after its slot was freed: record it as held, unless a
      # newer holder took the slot meanwhile (the mkdir loses; that holder is left alone)
      case "$res" in clean) exit 0;; clean-skip) res=SENTRY-SKIPPED;; esac
      lpr=$(gh api "repos/$repo/commits/$sha/pulls" --jq '.[0].number // empty' 2>/dev/null); lpr=${lpr:-${sha:0:7}}
      mkdir -p "$dir" 2>/dev/null; mkdir "$slot" 2>/dev/null || { echo "merge-slot: late $res for ${sha:0:10} NOT recorded — the $repo slot has a newer holder; tell that lane" >&2; exit 0; }
      echo "$lpr $sha late.$$ $res" > "$hf"; echo "merge slot for $repo is now held ($res, late re-run of ${sha:0:10}): the next merge in this repo takes MERGE_SLOT_ACK=$lpr once this result is dispositioned (deploy.md)"; exit 0
    fi
    rd
    # this merge's slot? by sha — or, when the merge was interrupted before its sha was recorded, by the PR the sha belongs to
    if [ "$hsha" != "$sha" ]; then
      [ "$hsha" = pending ] && [ "$(gh api "repos/$repo/commits/$sha/pulls" --jq '.[0].number // empty' 2>/dev/null)" = "$hpr" ] || {
        case "$res" in clean|clean-skip) ;; *) echo "merge-slot: $res for ${sha:0:10} NOT recorded — the $repo slot belongs to PR#$hpr; tell that lane" >&2;; esac; exit 0; }
    fi
    case "$res" in
      clean)
        # a watch that only now ends clean frees the slot; a RE-RUN over a held result frees it only when it read every
        # signal (no --skip-sentry) and no REVIEW line is pending — those age out of the query window unattributed
        if [[ "$hstate" != *REVIEW* ]]; then
          # under the ACK handoff's one-instant mutex: of a settling run and an acknowledged acquire one wins, and the
          # holder is removed only if it is still the record that was read (Codex, skills PR#60)
          [ -d "$slot/ack" ] && [ "$(age "$slot/ack")" -ge 1 ] && rmdir "$slot/ack" 2>/dev/null
          was=$hline; mkdir "$slot/ack" 2>/dev/null || { echo "merge slot for $repo is changing hands this instant — NOT released; re-run postmerge.sh"; exit 0; }
          rd; if [ "$hline" = "$was" ]; then rm -f "$hf" "$slot/prev"; rmdir "$slot/ack" 2>/dev/null; rmdir "$slot" 2>/dev/null; echo "merge slot for $repo released"
          else rmdir "$slot/ack" 2>/dev/null; echo "merge slot for $repo changed hands this instant — left to its new holder (PR#$hpr)"; fi
        else echo "merge slot for $repo stays held ($hstate): a re-run does not clear it ($([ "$res" = clean-skip ] && echo 'Sentry was skipped' || echo 'its REVIEW lines still need attributing')) — MERGE_SLOT_ACK=$hpr once it is dispositioned"; fi;;
      *)
        [ "$res" = clean-skip ] && res=SENTRY-SKIPPED
        # Serialize every settlement with ACK handoff, and retain a newer holder.
        [ -d "$slot/ack" ] && [ "$(age "$slot/ack")" -ge 1 ] && rmdir "$slot/ack" 2>/dev/null
        was=$hline; mkdir "$slot/ack" 2>/dev/null || { echo "merge slot for $repo is changing hands this instant — $res NOT recorded; re-run postmerge.sh"; exit 0; }
        rd
        if [ "$hline" = "$was" ]; then
          echo "$hpr $sha $htok $res" > "$hf"
          echo "merge slot for $repo stays held ($res): the next merge in this repo takes MERGE_SLOT_ACK=$hpr once this result is dispositioned (deploy.md)"
        else echo "merge slot for $repo changed hands this instant — $res NOT recorded; left to PR#$hpr"; fi
        rmdir "$slot/ack" 2>/dev/null;;
    esac;;
  *) echo "merge-slot.sh: unknown command '$cmd'" >&2; exit 2;;
esac
