---
name: sdk-upgrade-adoption
description: >-
  Walks a Claude Agent SDK / bundled Claude Code CLI version bump for NetPilot end to end
  and turns what the bump adds into a feature-adoption GitHub Project — research what is
  new, audit NetPilot's agent workflow against it, keep only what is relevant and
  beneficial to the NetPilot agent flow, file the board with issues, and leave Lin only
  the product/policy gaps. Use when Lin asks to bump, upgrade, or evaluate the
  claude-agent-sdk or its CLI, when Renovate surfaces a new SDK version, or when someone
  asks "what's new in the SDK and should we use it".
---

# SDK upgrade → adoption board

Created 2026-09-06 from board 20 (bump 0.2.130 → 0.2.152) and board 21 (its follow-ups),
where Lin reviewed twelve candidates one by one. The point of this skill is that next time
the agent runs the whole thing and hands Lin a filed board plus the few decisions that are
his — **not** that every new feature gets adopted. Relevance and benefit to NetPilot's agent
flow decide; novelty never does.

Skills this one leans on (load them at the named step, do not restate them): `dev-workflow`
(the bump PR and every follow-up PR), `project-management` (the board contract),
`issue-labeling`, `prompt-engineering` (any agent-facing text a follow-up touches),
`feature-research` (only when a candidate is a NEW product feature rather than an adoption),
`probe-testing` (every probe this skill asks for — the run, the verdict, and the lab cleanup).

Reference files (one level deep):
- `decision-patterns.md` — how Lin decides adopt/probe/drop; apply these BEFORE asking him.
- `issue-shapes.md` — the four issue templates the review settled on (observe-first,
  probe-only, gated phase, batch cleanup) and the label rules for each.
- `bump-battery.md` — the bump PR's verification battery (slim vs full), the billing check,
  and the tripwires that fire on a bump.

## The checklist

```
SDK upgrade → adoption:
- [ ] 1. Bump first (pin-only PR, battery from bump-battery.md, deploy, billing check)
- [ ] 2. What's new (SDK + CLI changelogs, verbatim; SDK surface diff at the type level)
- [ ] 3. Audit our workflow against it (Explore fan-out; hand-rolled mechanisms map)
- [ ] 4. Benefit map (every item bucketed: adopt now / probe first / later / drop)
- [ ] 5. Apply Lin's decision patterns → bucket moves, gaps list
- [ ] 6. Report artifact + design issue + board with ALL issues filed
- [ ] 7. Morning brief to Lin: what is filed, what only he can decide
```

## 1. Bump first, features after

The bump is a billing-class change (never-auto; Lin delegates merges per board). It ships as
a **pin-only PR** — no feature adoption rides on it — verified with the battery in
`bump-battery.md`. Two things always move with a CLI bump and are checked there: the
bundled CLI's **pricing table** (what users are charged) and its **tool registry** (new
harness tools arrive default-open; the bundle-registry test denies them). Everything
in steps 2–7 happens after the bump is live, against the bundled CLI that is actually
running.

Target version: the newest SDK whose bundled CLI carries the behavior the work needs
(2026-09: the `fable` alias only resolves to Fable 5.1 on CLI ≥ 2.1.257 = SDK ≥ 0.2.150);
otherwise simply the latest.

## 2. What's new — verbatim, not summarized

1. SDK changelog, every release between the pins, quoted in full (most releases are
   "CLI bump only"; the few with API changes carry the whole value). Then diff the installed
   SDK against the old sdist at the type level: new `ClaudeAgentOptions` fields, new
   exported types, new client methods (`pip download <old> --no-deps` into scratch, then
   compare `types.py` / `client.py` / `__init__.py`).
2. CLI changelog for the bundled range, filtered to what touches a headless/SDK session:
   options, message types, hooks, subagents, MCP, sessions/resume/compaction,
   models/effort/thinking, permissions, cost reporting. Mark entries beyond the bundled
   CLI as "next bump".
3. Where a changelog line is vague, `strings` the bundled binary for the feature's
   identifiers before claiming anything about it.

## 3. Audit our workflow against it

Fan out one Explore agent over `app/agents/**` and `app/services/chat_orchestrator.py`
with the audit brief from board 21 (BE#696): per area — files, mechanism, SDK options
used, private-API reaches (`_internal`, underscore attrs, subclassing), and every
**hand-rolled mechanism that re-implements something a harness could provide** (state
tracking, retries, custom message parsing, transcript handling, compaction estimation,
cost bookkeeping). End with the five most fragile mechanisms. That list is what the new
features get matched against; a feature that does not land on a hand-rolled mechanism or
a felt product problem is "later" or "drop" by default.

Verify every claim about our code by reading it (file:line), never from memory — the
board-21 review corrected the report twice this way (the error ladder's text comes from
in-stream results, not exceptions; edit/regenerate are frontend re-sends).

## 4. Benefit map — every item gets a bucket

For each candidate: the NetPilot pain it addresses, change shape (tiny / small / medium /
arc), guardrail class (does it touch a never-auto surface?), evidence needed, and ONE of:

- **adopt now** — small, reversible, no guardrail exposure, replaces a hand-rolled
  mechanism or closes a hazard. Always shipped as **observe first**: log the new signal
  beside the current heuristic for a week, then switch, then delete.
- **probe first** — the value is real but behavior on OUR auth path (OAuth Max pool,
  Postgres session store, bundled CLI) is unverified; the probe's findings decide GO/NO-GO
  and the design.
- **later** — real but no felt pain today; row only, no issue.
- **drop** — UI-only with no product plan, duplicates what the platform already does for
  us, or Enterprise/managed features that never reach a headless OAuth session.

Be honest about code reduction: count lines before claiming a cleanup; most SDK primitives
replace *detection*, not the retry/decision structure around it (BE#699). Say "robustness,
not a line-count win" when that is the truth.

## 5. Apply Lin's decision patterns before asking him

Read `decision-patterns.md` and move buckets accordingly. The outcome of board 21: of
twelve candidates, four were adopt-now, five probe-first, one dropped, two folded into
other issues — and only three questions were genuinely Lin's. Anything that is a
mechanism question (how, where, what fallback) is the agent's; anything that is a product
or policy question (audience, defaults, margins, what a control means to a user) is Lin's
and goes on the gaps list with a recommendation.

## 6. Deliver: report + board with everything filed

1. **Report artifact** (use available artifact tooling): what changed (verbatim table), CLI
   changes that touch us, the audit map, the ranked benefit map with buckets, a build
   sequence, "what should stay", "next bump watch". Publish; link it from the design issue.
2. **Board** (`project-management`): design issue = item #1 holding the benefit map and a
   decisions ledger; then file EVERY adopt-now and probe-first item using the shapes in
   `issue-shapes.md`, attached to phases where they are gated; one **batch cleanup** issue
   (`agent/stop` until its trigger) collecting every "delete after the observation week";
   "later" and "drop" as readme rows only, with the reason. Labels: observe/probe issues
   `agent/hold`; anything gated on a probe or on Lin `agent/stop`.
3. **Readme** per the contract, with a Pending-on-Lin section that lists ONLY the product/
   policy gaps, each with the agent's recommendation.

Nothing starts until Lin says go (board 21: "just create a project shell, I need to review
first" — he wants to read the board before any lane runs). Do not launch lanes from this
skill.

## 7. Morning brief

One artifact: what shipped (the bump), what is filed, the gaps with recommendations, and
the recommended start order. End there.

## Gotchas (verified)

- The reconciler catches a bundled-CLI price change as a "drift" alert within ~90 min of the
  bump; the change itself is what users pay from that moment on. Check the reconciler
  before the alert fires, decide with Lin whether the expected side follows the official
  sheet (board 20: it does — "charge exactly what the upstream CLI charges"), and never
  present it as a billing bug (BE#694, 2026-09-06).
- The bundle-registry tripwire failing on a bump is the mechanism working: classify each
  new tool DELIBERATELY (deny by default; sanctioning is Lin's), and add them to
  `DANGEROUS_TOOLS` so a later rename forces a re-audit (BE PR#688 R1–R3).
- A `gh pr ready` flip may mint no real CI run even with no outage; close/reopen the PR on
  the same head (`dev-workflow/merge.md`, "CI never ran").
- Lin's own test of a shipped model feature is verified backend-side by joining
  `messages.cost_usd` to `claude_session_store` usage per session: recorded == expected to
  the cent proves both the served model and the CLI's price row (board 20, 2026-09-06).
