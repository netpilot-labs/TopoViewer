---
name: prompt-engineering
description: NetPilot's rulebook for writing and editing AGENT-FACING PROMPTS — system prompt sections, MCP tool and parameter descriptions, hook/deny/error texts, subagent prompts, and skill text the agent reads. Use before touching any of them (backend `app/agents/prompts/`, `app/agents/workspace/prompt.py`, `netpilot_server.py` tool registrations, containerlab-mcp `tools/*` docstrings + `server_instructions.md`, `claude_client.py` deny texts, `workspace/rules.py`) and before ANY change that alters what the agent is told — new tool, changed schema, new instruction, new refusal message.
---

# NetPilot prompt engineering — system & tool prompts

The agent prompts (backend `app/agents/prompts/`, `app/agents/workspace/prompt.py`, tool
descriptions, hook/deny texts) are **core business assets**. This skill is the single
reference for editing them; the principles here were established and battle-tested in the
BE#331 prompt review (2026-08-02/03). Every prompt PR cites the rule it applies.

> **THE MANDATE (Lin, 2026-08-07):** clear and concise rules ONLY — never a junk,
> confusing wall of text. Every sentence an agent reads is billed on every turn and
> competes for its attention; text that does not change behavior makes the text that
> does harder to follow. When you cannot decide whether a line stays, it goes.

## The four-layer placement model

Instructions live in the cheapest layer that can carry them. Know all four before editing any:

| Layer | What | Cost | Editing rule |
|---|---|---|---|
| **L1 — CLI built-ins** | Tool descriptions + subagent prompts inside the pinned Claude Code binary | Always on, immutable | Cannot edit. MUST know what they say (extract from the pinned binary, verbatim). Compensate in L2 only where they MISLEAD in our context |
| **L2 — our system prompt** | Mode base + async section + workspace section + date | **Every turn** — most expensive | Carries ONLY: undiscoverable maps (absolute paths, UI panel layout), cross-tool workflow + WHEN, counter-arguments to misleading L1 text, hook-backed deliberate contradictions |
| **L3 — our tool descriptions** | MCP registrations (netpilot_server, file_tools, memory tools, workspace_delete/move…) | Loaded with the tool | Single-tool HOW: usage, params, limits, per-tool recovery |
| **L4 — hook/deny/error texts** | PreToolUse/PostToolUse, validation rules, can_use_tool | **Zero until the mistake** | The cheapest teacher. Every deny names the concrete next action; corrections that only matter on error live here, never in L2 |

**L3 serving on fastmcp 3.x (containerlab-mcp; verified clab#151, 2026-08-19):** fastmcp
parses google-style docstrings — the agent receives ONLY the docstring's preamble as the
tool description; the `Args:` section renders into per-parameter schema descriptions
(agent-visible, attached to each param); the `Returns:` section is STRIPPED and never
reaches the agent. So: upfront semantics (result contracts, non-inferable warnings) go in
the preamble; reactive teaching rides IN the tool's response; `Returns:` is source-only
documentation. The served surface AND the parsing behavior itself are pinned in clab
`tests/tool_tests/test_tool_descriptions.py` — verify against a served `list_tools`, never
by reading the docstring in source (the symptom points the wrong way: the source LOOKS
agent-facing).

## Core rules (Lin, 2026-08-02)

1. **Clear and concise — best agent UX at least context cost.** Density beats brevity: a line
   survives only if it is load-bearing; compression must never drop an instruction (compress
   prose, not meaning). The metric is instruction-following quality, not character count
   (~2k tokens total is lean for a production agent; creep shows up as compliance decay).
2. **No duplication between system prompt and tool prompts.** Tool prompt = that tool's
   usage/HOW. System prompt = WHEN to use it, how tools work together, and the workflow that
   controls related tools. If a sentence could live on a tool description, it does.
3. **Planning vs execution modes stay honest.** A mode base carries only what is true and
   actionable in that mode — never advertise tools, files, or actions the mode cannot perform
   (the VM FILES lesson: planning had upload/export guidance for tools that don't exist there).
   Text shared by both modes lives ONCE in `prompts/shared.py` constants, interpolated.
   Skills are NOT mode-gated: skill directories are granted per BUNDLE and are the same in both
   modes (`skill_dirs_for(enabled_bundles)` → `add_dirs`; VM Sandbox brings Design's too), so
   "planning lacks skill X" is never true — only a custom agent's bundle subset can lack one (BE PR#966).

## Extended rules (from practice — RATIFIED by Lin 2026-08-03, after three review rounds applying them)

4. **Verify the owning layer EMPIRICALLY before editing.** Before keeping, cutting, or
   compensating: probe live behavior (subagent probes, real transcripts) AND grep the pinned
   binary. Never assume a behavior is ours (the "Read-dedup guard" that turned out to be
   CLI-native) or that the CLI doesn't already teach a rule (the naming ban taught in the
   subagent's own prompt — our sentence was redundant).
5. **Budgets with teeth.** Token caps are test-enforced (workspace section: 490), measured at
   deploy-realistic WORST case — real `generate_session_id()` shapes, max-length ids, fixtures
   drift-pinned against the live generator. Raising a cap requires a design note; funding new
   text means tightening non-pinned prose, never weakening the test. A "measured minimum" is
   found by SCANNING candidate budgets against the worst-case render + floor assertions, never
   by adding the new text's token delta to the old cap — the recovery listing sizes itself
   from budget headroom at whole-name granularity, so delta arithmetic overshoots
   (BE PR#581, 2026-08-24: clause delta said 823+18=841; the scan measured 839).
   An execution-prompt addition is bound by the CUSTOM render cap (`CUSTOM_RENDER_MAX_CHARS`), not
   the default base's, and moves a third pin outside the prompt suites —
   `tests/unit/test_agents/test_client/unbound_compose_snapshot.json`, regenerated with
   `UPDATE_UNBOUND_SNAPSHOT=1 uv run pytest tests/unit/test_agents/test_client/test_factory.py`; only
   the full unit suite shows it. A sentence tightened to fund it is a prompt edit too — re-read it for
   meaning (BE PR#954, PR#957).
6. **Every load-bearing line is test-pinned; every edit is red-proven.** Pins port
   intent-preserving when wording changes (never delete an assertion to make an edit pass).
   Cuts get an ABSENCE pin plus a recorded re-add trigger (docstring + umbrella row) — e.g.
   "re-add only if a future pin drops the native teaching." A pin on a hard-wrapped guide folds
   whitespace first (`" ".join(text.split())`): a phrase that straddled a wrap failed after a re-flow
   with the fact intact (BE PR#958).
7. **Registry-derived, never hand-listed.** Mount lines, extension lists, subagent scopes,
   tool names render from the source of truth (`registry.py`, single-sourced constants) so the
   prompt cannot drift from the code or advertise a disabled surface (which buys a guaranteed
   deny and a wasted turn). **Text derived from a set of toggles (per-agent tool families) is
   honest per SUBSET, and a composite line's LABEL can lie while every tool it names is
   callable:** pin it by scanning every subset in the test, and gate the label on the family it
   means — filtering tool names alone rendered `DEPLOY: set_configs → execute_commands` under a
   lab_lifecycle-off agent (BE PR#766, 2026-09-13; `WorkflowStep.anchor`).
8. **Literal absolute paths only — no placeholders, no shorthands.** Agents echo shown string
   shapes into tools verbatim (the relative-Glob incident: the prompt's own `files/TASK.md`
   shorthand reproduced the failure). Repeating a long real path is a safety property, not
   waste. **Same for call shapes**: a signature hint must show the shape the tool actually
   accepts — a stale scalar hint against an array schema buys a refusal on first use
   (BE#430, 2026-08-06).
9. **A tool limit the model would otherwise design around is stated as a refusal plus the
    concrete alternative, never as a soft "leave X out".** Measured (T2, prod model, three arms,
    BE PR#929 + skills PR#49): "IPv4-only IP plan — leave IPv6 out of it (IPv6 goes in the
    device configs)" changed nothing on a dual-stack request (5 IPv6 subnets in the first
    `design_topology` call, the transcript never mentions it); "IPv4 ONLY — any IPv6 CIDR or
    address anywhere in l3_design is refused. Dual-stack lab: put the IPv4 half here and write
    the IPv6 addresses in the device configs only." put 0 IPv6 in the first call — in BOTH
    positions (head clause and rule (1)), so the content carried it, not the placement.
    **The alternative a rule states gets ACTED on:** when the choice is the user's, the rule
    says so ("give the user … the choices: A, B, or C"), never a bare "make it smaller"; and a
    percent names its base ("15% of mem_total_mib") (BE PR#934; evidence on BE#925).
10. **Cache-friendly assembly order.** Static blocks → per-session dynamic → date anchor last.
   The stable prefix is what prompt caching serves at ~10% price every turn; never insert
   volatile content above stable content.
11. **Deliberate L1 contradictions must be enforcement-backed and guarded.** Our prompt may
    out-argue the binary ONLY where a hook makes our version true (TaskStop session-scope,
    no-resume), and the source carries a doc guard against "fixing" the text back toward the
    CLI's teaching. The INVERSE dependency is pinned the same way: a line CUT because the
    binary teaches it natively ships with a bundle-pin test that greps the teaching out of the
    bundled CLI (test_sdk_bundle_registry pattern; BE#440 pinned three — AUQ restraint,
    background-by-default, SendMessage queue-receipt) — an SDK bump that drops the string fails
    CI, and the fix is re-adding the prompt line in the bump PR.
12. **Honesty and billing disclosures survive every compression.** Lines mandating truthful
    narration (never claim a read/steer/save that didn't happen; "tracked unchanged, not
    freshly verified") and cost-relevant disclosures (a relaunch is a NEW billed task) are
    never cut for tokens — Codex correctly blocked one such cut in review.
13. **A schema change is a prompt change.** New/changed tool arguments touch L3 (the
    description and every parameter description), L2 (any signature hint), and L4 (deny texts
    naming the old shape) — plus any PreToolUse gate that READS those arguments, which must be
    updated in the SAME PR (a gate reading a field the tool no longer uses silently allows;
    BE#430's subagent delete gate). Sweep all four layers before calling it done.
    **A NEW tool is also a permission change — the backend allowlist is a fifth surface in a
    different repo:** every new `mcp__containerlab__*`/`mcp__netpilot__*` tool must be added to
    `MCP_TOOLS`/`SHARED_TOOLS` in backend `app/agents/client/tool_surface.py` (`claude_client.py` re-exports them) in the same wave, or the
    `can_use_tool` safety net denies it in production ("not currently permitted") while the
    server still advertises it. Direct-MCP bench validation bypasses that permission chain, so
    only a production-path agent turn can catch the miss (`execute_dialog` shipped with guides
    + FE renderer while prod denied every call; BE#557, 2026-08-19).
Read [acceptance.md](acceptance.md) before every prompt edit: it owns the review-umbrella
process, skill-loading validation, behavioral acceptance probes and current-VM-package rule.

## Quick pre-edit checklist

Layer identified empirically? · Duplicates an L1/L3 text? · Mode-honest? · Registry-derived
where possible? · Call shapes match the real schema? · Gates reading those args updated? ·
Pins ported + red-proven? · Budget test green at worst case? · Honesty/billing clauses
intact? · Acceptance probe + decision rule written first (rule 16)? · Umbrella row + re-add trigger recorded?

## Related

Executing the PR that carries a prompt change (worktree → CI+Codex → merge) is
`dev-workflow`; grading agent BEHAVIOR after a prompt change is the product test under
`tests/product/` (`dev-workflow` authority.md `agent/hold` rule: agent-driven, judge-graded — never keyword matching).
