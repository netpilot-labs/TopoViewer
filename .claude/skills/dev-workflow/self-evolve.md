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
