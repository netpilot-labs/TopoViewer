# Evolution log

## 2026-10-06 — Shared configuration setup

Moved the existing skill into the shared authoring and regeneration flow.
Its instructions, references and scripts keep their existing behavior.
Record future applied changes here in the canonical source.

## 2026-10-07 — merge 500 diagnosis; post-flip stop clause (PR #201, BE PR#1008 learning pass)

`scripts/merge.sh`: a `gh pr merge` answered with GitHub's "Something went wrong while executing your
query" is named on the NOT MERGED line as a GitHub-side wait (or an installation-token failure, gh
cli#7213) with the instruction to re-run from `--dry-run` in 5-10 min; no wait loop inside the step.
`review.md`: after round-cap decision (a), a post-flip finding inside the mechanism just fixed that fails
the exposure test is a residual; the fix-now categories still fix, any round.

## 2026-10-07 — wave-2 lessons; re-request BROKEN names a GitHub write outage (PR #197, netpilot-skills#195)

`scripts/pr-gates.sh`: the two "could not post the re-request" BROKEN lines add the third reading — GitHub
answering comment writes with HTTP 500 (skills PR#200) — and the operator action (post `@codex review` by hand,
re-arm); a Codex "usage limits" reply after the latest request is recognized (`CODEX_QUOTA`) and the watch exits
NOT READY without the 5-min re-request. `scripts/pr-threads.py`: the usage line states the sha is the full 40-char head oid. Lesson lines in
merge.md, lanes.md, review.md, shell.md; one stale review.md bullet pruned.

## 2026-10-08 — ci-wait names a run minted just before `--since` with the re-run to make (BE PR#1023, PR#1026)

`scripts/ci-wait.sh`: `--since` stays a strict lower bound (a draft-era run on a repo whose drafts run
CI must never pass — Codex skills PR#208 R2 turned down a 120 s grace for that reason). On every path
that ends without a qualifying run, and only after the 120 s discovery window (the action's own run
may still be becoming API-visible), the script names each non-skipped run on the same head minted in
the 120 s before the bound — per workflow, since one sibling can predate the cutoff while another
passes it — with its `created_at` and the re-run to make (`--since <created_at>`). The push or the
flip mints the run before a caller that records `since` afterwards, and both PRs sat 10 min on
"no run minted" for a run 1 s too old. Both scripts fail closed on an unparseable `--since`.
