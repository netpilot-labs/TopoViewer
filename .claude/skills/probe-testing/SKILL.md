---
name: probe-testing
description: >-
  Answers a question about NetPilot's agent behavior at the cheapest tier that settles it,
  using netpilot-probe-lab (the REAL production client on Lin's local Claude login), and
  leaves the lab clean. Use before merging a behavioral change on the agent path (prompts,
  tool descriptions or schemas, hooks, gates, deny texts, client options or env, an SDK or
  CLI bump, model or effort defaults), when a decision turns on how the agent actually
  behaves rather than on code reading, when a Codex finding assumes CLI or API behavior,
  or when a new vendor guide must be validated before it is baked into the backend.
---

# Probe testing (netpilot-probe-lab)

The lab runs the real `create_claude_client` (prompt assembly, tool surface, hooks, denies)
against scripted scenarios — no prod backend, no Neon. The runs cost cents; the process
around them is what burns Lin's window (2026-09-07 audit). This skill IS the procedure;
the lab's README/PROCESS are pointed at, never re-read wholesale.

## Quick-start (this is the pre-read)

- Run: `cd netpilot-probe-lab && <backend>/.venv/bin/python probe.py scenarios/<family>/<x>.json`
  (families: `smoke/` `vendors/<vendor>/` `flip/` `agent-studio/` `live-network/` `policy/`)
  (`--model`, `--dry-run`, `--readback` (0-token loaded-surface readback, recipes §I),
  `--reps N`, `--user-id/--session-id`; `NETPILOT_BACKEND_DIR=<worktree>`
  probes a worktree's code). Local Postgres (`netpilot-db`) up = real-seeded workspace sync.
- Scenario JSON keys: `name`, `mode` (planning|execution), `messages` (user turns),
  `model`, `timeout`, `stubs`, `keep_real`, `auq_answers`, `notes`, `max_turns`, `user_id`,
  `agent` (a bound custom agent `{name, prompt, disabled_families}` — Agent Studio, lab PR#53;
  `meta.json` `agent`/`agents`/`tool_search_enabled` are its T0 readbacks), `resume_life`,
  `claude_md` (a literal replacing the cwd memory index the lab materializes before every
  connect since lab PR#55 — recipes §I).
- Three swaps, all recorded in `meta.json`: netpilot tools keep real schemas with stub
  handlers (`keep_real` opts out per tool); execution mode gets a stub containerlab server
  unless `CONTAINERLAB_MCP_URL` points at a VM; hooks are real when Postgres is up.
- Read only if needed: `probe.py` lines 1–40 (schema + outputs), `harness.py` lines 1–35
  (fidelity contract). Never the whole files. `PROCESS.md` only for prompt-line challenges.
- Surface-specific facts (store/fork, effort/model, origin, checkpointing, budgets,
  parallel arms): `probe-recipes.md` — read the one row you need.

## When a probe is required

- Before merging a behavioral (not mechanical) change on the agent path; before deciding
  anything that turns on agent behavior — "will the model do X under Y?" is never answered
  by reading code (Lin, 2026-09-06); when a Codex finding assumes CLI/API behavior
  (`dev-workflow/review.md`; Lin's Max account is pre-approved) — each at the cheapest tier.
- After an SDK/CLI bump: the T2 main-flow run in `sdk-upgrade-adoption/bump-battery.md`.
- Vendor onboarding: the tiered battery in `add-vendor/references/probe-loop.md`.

## The ladder — start at the lowest tier that can answer, default n=1

| Tier | What | Cost |
|---|---|---|
| T0 static | code audit; `strings` the bundled CLI; `render_prompts.py`; hook unit tests in the backend; `validate_scenarios.py`; `probe.py --dry-run` (builds the client, applies edits/stubs, writes `meta.json` + `summary.json`, never connects) | 0 tokens |
| T1 replay | `probe.py --transport replay` on a recorded `events.jsonl` (lab Phase 3) — prompt assembly, hooks, ledgers, teardown, verdict; never a behavior claim | 0 tokens |
| T2 one live run | prod model, 1–2 turns with the measured behavior EARLY, `max_turns` + timeout, warm prefix when a rep exists, deterministic end-state check, Haiku rubric only if a rubric is needed | ~$0.07–0.13 |
| T3 escalate | n=2–3 as `--reps` forks of the T2 turn-1 (cache-warm); Sonnet judge for fabrication/taste; A/B old-vs-new venv only when a named contract may have moved | per run |

Escalate to T3 ONLY when: the T2 run contradicts the code audit; the verdict would be
LOAD-BEARING or NO-GO; or the question is a rate — which includes any before/after on a behavior
the baseline already shows SOME of the time: start at 3 warm reps per arm (`--reps 3`), both arms
on one base, `max_turns` just past the measured call (n=1 pointed the wrong way twice and the
baseline's spread took six runs to show, BE#948). Mechanism readbacks (control-request
responses, pid continuity, served model, field presence) are n=1 by definition. Model ×
effort matrices only when the decision IS the matrix. `bump-battery.md`'s "ONE live probe"
is T2, the norm.

## The run (checklist)

```
Probe:
- [ ] 1. Question as a falsifiable sentence + the decision it feeds (issue link) + the tier
        that can answer it + a budget line (runs, USD) written BEFORE the first run — per
        WORDING iteration: one up-front "3 runs / $3" was overrun 4× as each rewording
        earned its own run set (BE PR#934) — and per baseline top-up (six runs went out with
        no line, BE#948). A before/after also states its DECISION RULE here ("B at least a
        third lower, not worse on any scenario" → ship; else one rewording; else drop): it
        settled a 4% result and a 7-of-9 without a debate (BE#922, BE#948)
- [ ] 2. T0 first: code audit — is the behavior fixed by code? then --dry-run the scenario
- [ ] 3. Scenario: smallest that reaches the behavior (1–2 turns), stubs vs keep_real
        deliberate, `max_turns` set; validate_scenarios.py passes (it reads `scenarios/**`
        only and takes no path: a scenario outside the repo is validated by `--dry-run`)
- [ ] 4. Fidelity: prod model unless the question is model-invariant; Postgres up when the
        question touches sync/store; venv = main checkout or the bump worktree
- [ ] 5. ONE live run (T2); escalate only on the three triggers above
- [ ] 6. Grade: deterministic end-state first (calls.json, workspace-writes.json,
        workspace-db-rows.json, summary.json); judge only the behavioral remainder
- [ ] 7. Evidence on the driving issue: numbers, exact options, decisive lines quoted
        inline, the budget actually spent (summary.json); never a run-folder pointer
- [ ] 8. CLEANUP (below) — lab `git status --porcelain` empty, run folders gone
- [ ] 9. LEARNING PASS — every lesson this run taught goes into its home BEFORE the
        report: a fact → `probe-recipes.md` (or this file if always-on); a mechanism
        → the lab (kit/probe.py/scripts, one small PR); a scenario hint → the scenario;
        a rubric line → `reviews/rubrics/`. A pass that changed nothing durable is the
        exception (skill-maintenance charter; Lin 2026-09-08: "learn during the loop")
```

## Grading

- Product tests stay judge-graded, never keyword-matched (Lin's rule; `tests/product/
  README.md`). Deterministic checks take the mechanical part (routing, deny branches, sync
  ledger, served model, session identity, hook firing); the judge gets the remainder.
- One judge per BATCH of 3–4 runs on the same prompt/guide version, never per run; Haiku
  4.5 for rubric checks (calibrated once against existing judged transcripts), Sonnet for
  fabrication and taste; Haiku never decides LOAD-BEARING or NO-GO alone. Output = a fixed
  ≤15-line block (score, FIRED/AVOIDED table, friction list, proposed lines). Spawn judges
  in the FOREGROUND from the lane that owns the run (a background lane's judge reports to
  the coordinator instead).
- An A/B judge is BLIND to the arm: the outputs go to neutral files in shuffled order and ONE
  judge grades every output of a scenario, so one fact gets one grade. A recorded baseline is
  comparable only under the judge brief that scored it — a new brief re-judges the baseline
  too, budgeted up front (a claim-by-claim audit against rubric scores ended INCONCLUSIVE
  after $10 of runs, BE#922).
- Fabrication cross-check when a run wrote files: the `ok:true` paths in
  `workspace-writes.json` vs the transcript spans naming them — a 10-line diff, not a read.
- Verdict vocabulary: prompt-line challenges SAFE / LOAD-BEARING / INCONCLUSIVE
  (`DECISIONS.md`, PROCESS Stage 5); adoption/design probes GO / NO-GO with the numbers on
  the issue. A `max_turns` or budget stop is INCONCLUSIVE, not a fail.

## Always-on mechanics (verified)

- Run from the lab dir with the BACKEND venv's python; never launch a long probe from a
  worktree a merge will remove (`dev-workflow/setup.md`). **One consumer of the local Postgres at a time**: a probe (workspace
  seed + teardown) racing a backend `pytest tests/unit` on the same `netpilot-db` makes BOTH
  look broken — `TooManyConnectionsError` storms and `relation "organizations" does not
  exist` from the other side's schema reset (three concurrent consumers, LAB#59, 2026-09-17);
  a probe that dies before connecting shows `verdict ERROR` with only `meta.json` + `summary.json`.
  With sibling lanes on the machine, wrap the run in `dev-workflow/scripts/with-db-lock.sh <issue-id> …` (FIFO; its header
  has the rules). `--model` takes an alias or full
  id; `meta.json` records both; the served id is on `message_start`; cost is in `summary.json`.
- Scenarios with `between_actions` run ONLY through `scripts/run_flip_probe.py`; ones with
  `resume_life` (a second life resumed on the first's SDK session — the pool's recreate) ONLY
  through `scripts/agent_lives_probe.py` (lab PR#53).
- Deep multi-step VM flows expose static stubs — keep the measured behavior early or
  script per-call stub sequences. `keep_real` naming a retired tool aborts the run.
- A reusable lab script uses `lab/probe_kit.py` (lab 2b; until then copy the two contracts
  from `scripts/fork_probe.py`): identity, seed, owned-id teardown, self-contained verdict
  are the kit's; a new probe is turns + checks.

## Driving a PRODUCTION session headlessly (a product test with no browser; BE#866, 2026-09-18)

Clerk's Backend API cannot mint a production session (`POST /v1/sessions` is dev-only), but the cookie ticket flow works
from curl: `POST https://api.clerk.com/v1/sign_in_tokens {"user_id", "expires_in_seconds"}` (secret from `.env.prod`) →
`POST <CLERK_ISSUER>/v1/client/sign_ins` with `strategy=ticket&ticket=<token>` and a cookie jar (`Origin:
https://app.netpilot.io`) → `POST <CLERK_ISSUER>/v1/client/sessions/<sid>/tokens` returns a 60-second JWT, re-minted before
every call → `POST /api/v1/chat/message {"session_id": "netpilot-<user_id>-<ts>-<8 hex>", "message", "agent_id"}` streams
SSE; grade from the `tool_use` events. It is a real sign-in on the user's account: only under the owner's delegation, and
revoke the session afterwards (`POST /v1/sessions/<sid>/revoke`).

## Cleanup — the lab is a test rig, not an archive (Lin, 2026-09-06)

1. Evidence lives on the issue (or the case file for prompt-line challenges); a run folder
   will not exist tomorrow.
2. Delete every run folder the pass created (`runs/` is untracked; lab
   `git status --porcelain` must print nothing) and any `/tmp/ws/s/probe*` or
   `/tmp/user-memory-probeu*` it left — each by its full path, printed before the `rm`.
   **A pass never deletes anything under `~/.claude/`:** the harness teardown removes its
   own per-run `~/.claude/projects` dirs (recipes §F), and one that survives is left in
   place and named in the report. An improvised `rm -rf ~/.claude/projects/"$d"` with `$d`
   empty erased the machine's auto-memory and every session transcript (BE#928 lane,
   2026-10-01).
3. Commit a scenario only if it will be run again; delete one-offs. Never leave a
   probe-only edit in the backend checkout.
4. Keep-or-remove test for every file touched: run again → keep AND improve it (a lesson
   goes into `probe-recipes.md`, a scenario hint, a rubric line); guides a future run or
   defines a format → ONE exemplar; everything else is removed before reporting done.
