# The bump PR — verification battery and tripwires

Provenance: the 0.2.116 → 0.2.128 walk (2026-08-03, full battery), the 0.2.129 walk
(slim), and the 0.2.130 → 0.2.152 walk (BE PR#688, 2026-09-06, slim per Lin D8).

## Contents
- Slim vs full
- The battery
- Tripwires that fire on a bump
- Billing check after deploy
- Deploy duties

## Slim vs full

**Slim** (Lin, D8: "just end to end main flow works is fine") when the walk touches no
pricing/alias/contract move you already know of: static import check, bundle-registry test,
full unit suite, ONE live main-flow probe, drain-test nearest verification, reconciler
check after deploy. **Full** (the 0.2.128 pattern) when the CLI range moves pricing, aliases,
or message contracts, or the walk spans many versions: add the live OAuth probes for cost
semantics, >2-minute MCP call inline, hook matcher membership, AskUserQuestion injection,
and an old-vs-new venv A/B on any contract that looks changed.

## The battery

1. Pin + `uv lock`; keep `mcp` on 1.x (`mcp>=1.23.0,<2`) unless a walk deliberately takes
   2.x; README technology table version.
2. **Static private-API import check** — every `claude_agent_sdk._internal` reach must
   import on the new version (2026-09 list: `sessions._get_claude_config_home_dir` /
   `_sanitize_path`, `session_import.import_session_to_store`, `_query._transcript_mirror_batcher`,
   `client._query._send_control_request` (BE#712 live effort apply, 2026-09-07), logger names `_internal.query` / `_internal.transcript_mirror_batcher`). Grep `app/` for
   the current list; verify against the tag's source tree BEFORE installing.
3. `tests/unit/test_agents/test_sdk_bundle_registry.py` on the new binary, then the full
   `tests/unit` suite vs local PG (never two backend pytest runs at once).
4. Read the SDK changelog for contract deltas (new exceptions — `ResultError` is a
   `ProcessError` subclass; widened `Message` unions — the drain's isinstance chain must
   fall through; transport changes to in-process MCP — probe every planning tool's result
   shape).
5. **ONE live probe (probe-testing T2)** on the new venv: `netpilot-probe-lab`
   `probe.py scenarios/smoke/example.json` with `NETPILOT_BACKEND_DIR=<bump worktree>`;
   compare tool_result shapes and cost (`summary.json`) to the same scenario on the old pin.
   Items 2–4 above are T0 (no model call); the full-battery extras are T2 runs, one each,
   escalated only per the ladder's three triggers.
6. Frontend bump duty: the AskUserQuestion result template the frontend parses
   (`tool-ask-user-question.tsx`) — `strings` the new binary for the template text.
7. Bundled CLI facts to record in the PR: alias targets (`strings` for `claude-<model>-x-y`),
   env gates the backend sets still present (`CLAUDE_CODE_DISABLE_*`, `ANTHROPIC_DEFAULT_*`,
   `CLAUDE_CODE_AUTO_COMPACT_WINDOW`).

## Tripwires that fire on a bump

- **Bundle registry: unclassified harness tools.** New CLI tools arrive default-open. Deny
  each deliberately in `DISALLOWED_TOOLS` with a dated comment, record them in the
  workspace snapshot test's `DELIBERATE_BASE_DENY_ADDITIONS`, and add them to the registry
  test's `DANGEROUS_TOOLS` watchlist so a rename forces a re-audit. Sanctioning any tool is
  Lin's (issue #219).
- **Thinking/effort behavior.** Always-on-thinking models reject explicit `disabled`; the
  CLI clamps effort when thinking is off. The effort a headless session actually ran at is
  on every transcript line (`entry->>'effort'` in `claude_session_store`) — query it, never
  assume the interactive default. Re-read `factory.py`'s thinking branch against
  the changelog's model/effort lines.
- **Hook names beyond the SDK's `HookEvent` Literal.** `PreModelSwitch`/`PostModelSwitch`
  work through `options.hooks` on CLI 2.1.259 although SDK 0.2.152's Literal does not name
  them (typing only; the registry dict is `dict[Any, …]`). They are bundle-pinned in
  `REQUIRED_HOOK_EVENTS`; a bump that renames them breaks the in-place model switch's audit
  line first (BE PR#725, 2026-09-07).
- **Alias resolution.** `opus`/`sonnet`/`fable` targets can move between CLI versions
  (fable → 5.1 from 2.1.257); the pins in `env.py` are the no-deploy levers.

## Billing check after deploy (the one that pages)

The bundled CLI's pricing table is what users are charged (`messages.cost_usd`). The
reconciler's expected side (`RATES_BY_PREFIX`) must agree with the official sheet, and the
deploy-check fires ~90 min after the scheduler restarts. Before it does: join
`messages.cost_usd` to `claude_session_store` usage on single-turn sessions before and after
the deploy (db-access, read-only); recorded == expected to the cent identifies which rate
the CLI bills. If the CLI moved (0.2.152: Sonnet 5 $3/$15 → $2/$10, now official), the fix
is the expected-side row + docstring, framed as alerting-only, and the policy is Lin's
standing rule: charge exactly what the upstream CLI charges (BE#694). Add rate rows for
new model ids (longest-prefix + delimiter match; Fable 5.1 cache reads are 0.025×).

## Deploy duties

`needs/drain-test` on the bump deploy: originate a long lab turn if a session is available;
otherwise do the nearest verification (cutover log scan for repaired-transcript /
graceful-disconnect lines, health samples at cutover and +5 min) and SAY it was nearest,
never that the drain was exercised. Prove the deployed version in-container:
`railway ssh -- sh -lc "cd /app; .venv/bin/python -c \"import importlib.metadata as m; print(m.version('claude-agent-sdk'))\""`.
The scheduler service deploys the same commit — watch it too when the change touches a
scheduled job (the reconciler lives there).
