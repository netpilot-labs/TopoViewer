# Probe recipes — surface-specific facts (read the row you need, not the file)

| Surface | Section |
|---|---|
| Session store, resume, fork, rewind | §A |
| Effort, model switch, control requests | §B |
| Turn origin, CLI-initiated turns, between-POST probes | §C |
| File checkpointing / `rewind_files` | §D |
| Budgets (`max_budget_usd`, `task_budget`) | §E |
| Parallel arms, process continuity, per-run dirs | §F |
| Grading from `events.jsonl` (thinking blocks, served model, tool calls) | §G |
| Tool-surface readbacks (deny hiding needs HTTP MCP), AUQ scripts, result-stub fidelity | §H |
| Loading surface: CLAUDE.md memory files, skills, `--readback` | §I |

## §A Session store, resume, fork, rewind
- The transcript store is OFF in the harness unless `TRANSCRIPT_STORE_ENABLED` is exported
  BEFORE the backend modules import and `init_transcript_pool()` runs — a store-backed probe
  that skips this silently tests the JSONL path (BE#704 probe, 2026-09-07).
- `SessionMessage.message` holds the payload, not `.content` (same probe).
- A forked session stays cache-warm only inside the SAME app session id: the system prompt
  embeds session-scoped workspace paths, so a new app session id costs a cold prompt.
  `probe.py --reps N` forks reps from a shared turn-1 for this reason — so reps SHARE the
  session's workspace/DB state by design (`summary.json` → `lives[].state_carried`); a rep
  that must not see earlier writes is a separate scenario run, not a rep (lab#41).
- Reference implementation: `scripts/fork_probe.py` (ordered-lineage check, guard refusal
  text, owned-id teardown).
- **A question about ONE late moment (the closing report, the step after a tool result) is
  forked, never rebuilt.** Two-turn scenario — turn 1 = the task + "do not write your report
  yet — end with READY FOR REPORT", turn 2 = the measured ask — run with `--reps N`: the base
  turn runs once and every rep replays only turn 2. To change the SYSTEM PROMPT per arm, wrap
  `harness.build_probe_client` and pass `prompt_edits` on the chosen rep builds; the CLI applies
  the new prompt on a resumed fork (readback: a fork quoted the edited line). Budget each arm's
  FIRST fork as one uncached read of the whole transcript (~$0.40–0.50 on a 40-call lab), the
  rest read cache ($0.05–0.07): 12 closing reports over 3 bases cost $2.54 against ~$20 for 12
  rebuilds, after six full rebuilds had failed to separate two wordings (BE#922, 2026-10-02).

## §B Effort, model switch, control requests
- Cheap readback: the CLI `get_settings` control request (`applied.effort` /
  `applied.model`); `apply_flag_settings {settings:{effortLevel}}` changes effort live;
  `--debug-to-stderr` via `extra_args` turns the CLI's clamp/retry lines
  (`… clamped to 'high'`) into quotable evidence (BE#711 probe, 2026-09-07).
- `set_model` keeps the live effort only for models in the CLI's table; re-apply effort
  after the switch and read both back once. The prompt cache is model-keyed: the first
  post-switch call is a cold write on every path (BE#708 probe, 2026-09-07).
- The CLI emits a `system/init` per query in streaming mode — "exactly one init" never
  proves no restart; prove continuity with the subprocess pid / `returncode is None`
  before and after (lab PR#29). Reference: `scripts/setmodel_probe.py`.

## §C Turn origin and CLI-initiated turns
- Origin lives ONLY on `ResultMessage.origin` (turn end); no `UserMessage` carries one;
  human/followup turns arrive with `origin=None` unless the caller stamps it. Plain
  `probe.py` never sees CLI-initiated turns (task-notification, auto-continuation) because
  `receive_response()` stops at each `ResultMessage` — a between-POST probe needs a
  lingering `receive_messages()` reader as the driver (BE#700 probe, 2026-09-07).

## §D File checkpointing
- SDK 0.2.152 refuses `enable_file_checkpointing` together with a `session_store`
  (ValueError at connect), yet the CLI tracks Write/Edit backups anyway under the ephemeral
  `/tmp/claude-<sid>/file-history/` (off only via `CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING=1`);
  a store-materialized fork carries backup NAMES but no bytes, so `rewind_files` on a fork
  deletes new files and cannot restore modified ones. Cheap readback: the `rewind_files`
  control request with `dry_run: true` → `{canRewind, filesChanged, insertions, deletions}`
  (BE#706 probe, 2026-09-07).

## §E Budgets
- The `max_budget_usd` USD reminder the CLI injects each prompt is an `isMeta` attachment
  that never reaches the SDK stream — read pacing from thinking blocks and the model's
  text, not from events. Never cap a pacing/wrap-up probe with USD; use `max_turns` +
  timeout. `task_budget` has a 20k-token API floor on Sonnet 5 and 400s on the
  `claude-sonnet-4-6` fallback, so a sub-floor probe silently measures the fallback path
  (BE#709 probe, 2026-09-07). A budget-stopped run is INCONCLUSIVE, not a fail.

## §F Parallel arms, process continuity, per-run dirs
- `prepare_env()` chdirs to the backend checkout (pydantic-settings reads `.env` from cwd): a lab
  script that takes a RELATIVE scenario path must resolve it BEFORE `prepare_env` / the kit's
  `prepare_env`, or the file is looked up under the backend and the run dies before turn 1
  (`render_prompts.py --agent` and `agent_lives_probe.py` both hit it; Codex PR#53 R1, 2026-09-13).
- Launch parallel arms with explicit per-variable assignments, never a loop over spec
  strings (`set -- $spec` does not word-split under zsh — BE#706 probe, 2026-09-07). Prefer
  sequential arms in one process: arm A back-to-back (cache-warm), then arm B.
- A driver that imports `harness` must pass ABSOLUTE scenario paths: `prepare_env()`
  chdirs to the backend at import (BE#711 probe, 2026-09-07).
- The lab seeds its probe users/sessions rows into the LOCAL `netpilot` DB, which every lane
  shares — a sibling lane's migration moves it, and a column your worktree's models carry
  but that DB lacks fails the seed with `UndefinedColumnError` → verdict ERROR before turn
  1 (a schema signal, never a behavior one). Probe a migration-carrying worktree with
  `NETPILOT_PROBE_DB_NAME=netpilot_test` (a bare database NAME — the host stays localhost)
  after `DATABASE_URL=…/netpilot_test uv run alembic upgrade head` in that worktree (lab
  PR#58, BE#793 P14, 2026-09-14).
- The CLI creates `~/.claude/projects/<sanitized-cwd>/` for every run-unique probe cwd. The
  harness teardown removes the session files of the ids the run saw and, when the user id is
  run-minted, the project dir itself (a pinned `--user-id` keeps its dir by design); five
  lanes found nothing left to sweep (2026-10-01). There is NO manual sweep: a dir that
  survives is reported, never deleted (SKILL.md Cleanup).
- The bench lock (`probe.py` `_acquire_bench_lock`) is keyed on the `CONTAINERLAB_MCP_URL`
  STRING, so lanes that reach ONE bench through different local forward ports do not
  serialize (BE PR#933, 2026-10-01). Until the lab keys it on the bench itself, every lane
  wraps its probe in ONE agreed bench-wide file (`flock /tmp/<bench-name>.lock … probe.py …`)
  — never a probe's internal file (`/tmp/netpilot-probe-bench-<sha256(url)[:12]>.lock`): its
  own self-deadlocks, and two lanes wrapping each other's deadlock each other (skills PR#51).

## §G Grading from `events.jsonl`
- SDK dataclasses are serialized by FIELDS, never by class name: `"ThinkingBlock"` does not
  appear anywhere. Count thinking as `content_block_start` entries with `"type": "thinking"`
  (or the transcript's `[thinking]` tags); the served model is on every `message_start`;
  `thinking_tokens` is on the first call's usage. A class-name grep is a false NO-GO
  (board 22 Phase 4 proof, 2026-09-08).
- `calls.json` ledgers ONLY the in-process netpilot stubs and the stub containerlab handlers
  (`call_log`): a live HTTP MCP server's calls — a real `CONTAINERLAB_MCP_URL`, an attached
  custom tool set (`agent.enabled_toolsets`) — never land there, so an empty `calls.json`
  reads as "no call" while the transcript shows it. Grade live-server calls from the
  `[tool_use]` blocks in `transcript.md` / `events.jsonl` (lab PR#58 Codex R1, 2026-09-14).
- `meta.json` echoes the SCENARIO's options, not the resolved ones: a scenario's
  `"thinking": false` is ignored since BE PR#724 and effort is the CLI default unless the
  scenario sets `effort` (lab#47). Read the resolved option from the factory line you are
  probing, or from `get_settings` (§B).

## §H Tool-surface readbacks, AUQ scripts, result-stub fidelity
- `disallowed_tools` does NOT filter the lab's in-process SDK MCP stubs (netpilot, the stub
  containerlab): a `mcp__containerlab__*` glob or a per-name deny leaves every stub tool in
  the CLI's init `tools` list — so an SDK-stub run is a false NO-GO for any "deny hides an
  `mcp__` tool" question. Measure it over an HTTP server (prod's containerlab transport): a
  throwaway `mcp.server.fastmcp.FastMCP("containerlab", host=..., port=..., streamable_http_path="/mcp")`
  registering the nine real tool NAMES, `mcp.run(transport="streamable-http")`, then
  `CONTAINERLAB_MCP_URL=http://127.0.0.1:<port>/mcp` — there the glob hid 9/9 and the name
  deny exactly its tool; the helper sub-agent's mirror (`AgentDefinition.disallowedTools`)
  measures the same way (BE#760 P1/P5/P10, 2026-09-13). In-process tools are hidden only by
  non-registration (`create_netpilot_server(disabled_tools=)`).
- A scripted `auq_answers` dict is keyed by the model's EXACT question text, which it
  paraphrases at will — the pool then returns no answer and the agent waits ("The user did not
  answer the questions"), which reads as "proceeds-after-yes MISSED". Script consent as
  `"auq_answers": "first-option"` (auto-answers every question with its first option) when the
  measure is "asks once, then proceeds" (BE#760 P4a, 2026-09-13). A free-text answer (a decline,
  an option the model did not list) is `{"*": "text"}` — it answers whatever was asked (lab PR#77).
- **Probing what a tool RESULT teaches** (`get_vm_status` answers a static stub unless the
  scenario lists it in `keep_real`): a stubbed result is the backend's REAL render, never
  hand-written — lab `scripts/vm_status_stub.py` (from a bench, or `--offline` for a VM picture
  no shared bench can be put in) — and every other stub that describes the same VM (`docker ps`
  / `inspect` / `free`) must agree with it: Opus verifies before deciding, and a contradicting
  or `[probe stub] …` reply turns the run into tool diagnosis, which is INCONCLUSIVE, not a
  behavior fail (BE#925, lab PR#76/#77; lab `reviews/rubrics/scenario-notes/policy.md`).

- **A REAL connector gateway behind the `live_network` tool set** (BE#866 rehearsal, 2026-09-18):
  export `LIVE_NETWORK_MCP_URL=<gateway ORIGIN, e.g. https://netpilot-2-gateway-production.up.railway.app>`
  (the factory appends `/connectors/<id>/mcp` — never pass the `/mcp` path),
  `LIVE_NETWORK_MCP_TOKEN=<the backend's CONNECTOR_GATEWAY_TOKEN from .env.prod>` (the backend↔gateway
  bearer, not a connector token) and `LIVE_NETWORK_CONNECTOR_ID=<connectors.id from
  register_connector.py --list>`; `--dry-run` shows the composed URL in `meta.json`. The probe takes
  a lock per gateway+connector — one live-network run at a time — and the device is real: P2 leaves
  its BGP neighbour behind. The connector-side rig (VM, cRPD lab, inventories) is `connector-deploy`.

## §I Loading surface — CLAUDE.md, skills, `--readback`
- The CLI does NOT load `CLAUDE.md` from an `add_dirs` directory by default — only from cwd
  (+ parents); `--add-dir` memory needs `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`, which
  production's CLI env never sets. Skills DO load from `add_dirs`: since BE#772 each enabled
  harness bundle's `app/agents/bundles/<key>/.claude/skills/` is an `add_dir` (default agent:
  21 skills + 11 CLI built-ins = 32; a web+workspace+subagents agent: 1 + 11 = 12; a bundle
  set with no skills is a legitimate empty `projectSettings` set — never "the backend root").
  Verified: `get_context_usage` `memoryFiles` = the cwd index only (lab PR#55, probe-lab#54,
  CLI 2.1.259, 2026-09-13); bundle counts on lab PR#56 (BE PR#773).
- A Workspace-OFF custom agent keeps the per-user cwd but the factory sets
  `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` in the CLI env (the claudemd loader returns `[]`; bundle-
  pinned in the backend) — its readback shows `memory_files = []`, which the lab's gate REQUIRES
  for such an agent (a loaded file = INVALID; lab PR#56, BE PR#773 Codex R1, 2026-09-13).
- Grepping the 200 MB bundled CLI: `ugrep` (the aliased `grep`) rejects `.{0,N}` context
  patterns on it (`exceeds complexity limits`) and a wide `.\{400\}` regex runs for minutes —
  extract context with Python (`bytes.find` + slicing, `errors="replace"`); a fixed-string
  `grep -a -c` stays fast (BE#772 lane, 2026-09-13).
- 0-token loaded-surface readback: `probe.py <scenario> --readback` (connect → `get_settings`
  + `initialize` + `get_context_usage` → disconnect; `summary lives[].cli_loaded`:
  `memory_files` path/type/tokens, `skills.skillFrontmatter` names + sources, commands,
  agents). The same block rides every live run; the per-query `system/init` (`tools`,
  `slash_commands`) is added there. The gate is EXACT: `memory_files` must be the one
  materialized cwd index and the `projectSettings` skills must equal the skill dirs under
  the client's `add_dirs` (an empty set is legitimate only when add_dirs carry none — the
  BE#772 bundle layout); a failed `get_context_usage`, a stray memory file or a missing
  skill is verdict ERROR, never RAN (lab PR#55, Codex R1–R4).
- The readback reports a skill's listing entry in TOKENS, not text, so it cannot show a
  truncated `description:` directly. The bound is the length: the bundled CLI cuts a listing
  entry at 1,536 chars, so hold a description to the shipped guides' 1,024 and pin it (backend
  `test_network_experiment_guide.py` does, for its guide). A tokens-per-character ratio far
  below an untouched guide's flags a gross cut only — it never proves there was none (BE
  PR#933, 2026-10-01).
- `meta.json` fidelity readbacks (lab PR#55): `options.cwd/add_dirs/setting_sources` (the
  factory's), `option_parity` (every post-factory option edit; undeclared = build error),
  `claude_md` (the memory index materialized in cwd before EVERY connect — the pool's
  pre-connect step, REAL `materialize_workspace` with Postgres up; a scenario `claude_md`
  literal replaces it). Before PR#55 the lab's cwd had no index: any "did the model see the
  memory index" claim from an older run is void.

