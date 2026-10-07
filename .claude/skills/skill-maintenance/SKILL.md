---
name: skill-maintenance
description: Maintains and evolves NetPilot's root skills (the canonical .claude/skills/ repo — dev-workflow, issue-labeling, project-management, prompt-engineering, add-vendor, golden-image, feature-research). Use when creating a NEW skill; when rewriting, refactoring, restructuring, or editing ANY existing skill or its reference files; when capturing a new rule, gotcha, or lesson; and at every learning trigger — a PR merged, an issue closed, a project closed, or a root cause resolved.
---

# Maintaining NetPilot's skills

Governs **every skill in the canonical repo** — the workspace root's `.claude/skills/`,
including this file (scope: Lin, 2026-08-15; charter: Lin, 2026-07-26). Skills are living
documents; keeping them correct is every session's job, not a request to Lin.

Two ways in — pick yours:
- **Authoring** (creating a new skill, or rewriting/refactoring/restructuring an existing
  one): start at **Format rules** — fetch the live Anthropic guidance first — then apply
  Placement, Single source, and the charter tier before shipping.
- **Learning** (a lesson to capture from work just finished): run **the learning pass** below.

## The learning pass

Run it at each trigger — never batch into "later"; later never fires:

- **A PR merges** (`dev-workflow`'s checklist step 12 IS this pass).
- **An issue closes** with a lesson beyond its PRs (a decline/defer rationale, a platform
  truth found in triage).
- **A project closes** (the fold-back step in `project-management` / `add-vendor` close).
- **A root cause is resolved** — incident, misdiagnosis, or debugging arc, whether or not code
  changed. A retraction is a first-class lesson: bake the diagnosis that would have prevented
  the wrong path, not just the fix.

Copy this checklist and work through it:

```
Learning pass:
- [ ] 1. Earned — the lesson passes ALL THREE earned-content tests below (else: no edit)
- [ ] 2. Placed — ONE owning file found via the placement rules
- [ ] 3. Deduped — grep the skills for an existing statement; update it, never restate
- [ ] 4. Tiered — fact-based edit (self-serve) or policy change (ask Lin)? See the charter
- [ ] 5. Shipped — edit in a scratch clone of the canonical repo (see the ship duty); for dev-workflow run the lint (ONE shell line, pointed at the WORKTREE's files):
        /Users/linzhu/agent-config/dev-workflow/scripts/lessons-lint.sh <your-worktree>/dev-workflow
        and clear its HARD lines (without the argument it checks its own, unchanged copy; when the
        script itself changed, run the worktree's copy: <your-worktree>/dev-workflow/scripts/lessons-lint.sh) (a soft-cap WARN means cut, or extract a concern to its own file, before adding); commit + push; sync-all.sh; commit consumers
```

## The earned-content test (every line passes ALL THREE)

1. **Paid for** — traces to a real observed failure, discovery, or decision, with a provenance
   tag (`(PR#216, 2026-07-24)`) — a tag, never the story; the full *why* goes to memory.
   Never speculative, never "might be useful".
2. **Non-derivable** — an agent could NOT work it out on the spot from the code, the tools, or
   native knowledge. Passes: undiscoverable maps (which repo/branch/file owns a thing), traps
   whose symptom points away from the cause, empirically measured facts. Fails: generic tool
   usage, standard practice, anything readable at the pointer's destination — point to the
   file instead of paraphrasing it.
3. **Not script-enforced** — the MECHANICS a script in the skill's `scripts/` already encodes (which
   channels a gate reads, how it matches, its timing and escalation) are not written out again: the
   script's header keeps the WHY in one line and the learning pass fixes the script, not a paragraph.
   The prose keeps what an agent needs to RUN it — the invocation, its place in the sequence, and the
   safety semantics (Format rules below) (Lin, 2026-09-27; board 30).

Filler weakens the load-bearing lines around it: when you cannot decide whether a line stays,
it goes. Drop lines whose failures stop reproducing (the vendor-guide rule, `add-vendor` 1-i,
applies to every skill).

## Placement — where a rule goes

- **How work is executed** (flow, gates, review loop, deploy watch, cleanup, guardrails) →
  `dev-workflow`. **Label meaning/triage** → `issue-labeling`. **Multi-issue initiatives** →
  `project-management`. **Any agent-facing prompt text** → `prompt-engineering`.
- **Domain runbooks own their domain end to end** — vendor onboarding → `add-vendor`, image
  builds/fleet → `golden-image`, upstream/provider research → `feature-research`. A lesson
  learned inside a domain lands in that skill, never in a workflow skill.
- **Repo-specific tooling** (a mypy flag, an env file, a CI quirk for ONE repo) → **that
  repo's `CLAUDE.md`**. Only genuinely cross-repo rules belong in a skill.
- **A concern that grows its own lifecycle** → its own new skill (a Lin decision — see the
  charter). One skill = one job; but the DEFAULT move for an outgrown section is extraction
  to a reference file, not a new skill.

## Single source of truth

State each rule in **exactly one place**; everywhere else links to it. If two skills (or a
SKILL.md and a reference file) need the same fact, one owns it and the other points (e.g. the
never-auto surface list lives in `dev-workflow` Guardrails; `issue-labeling` points there).
Restating is how skills drift and contradict.

## Format rules (Anthropic skill-authoring guidance; adopted Lin, 2026-08-15)

- **Rewriting, refactoring, or creating a skill? Fetch the LIVE guidance first:**
  <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
  (WebFetch). The bullets below are the adopted snapshot; the live page wins where they
  differ — and a difference is itself a learning-pass item (update this section).
- **Frontmatter `description` = discovery only.** It is pre-loaded into every session's
  context, so it carries exactly two things, in third person: WHAT the skill does and WHEN to
  load it, using the trigger words a session would match on (≤1024 chars). Principles, rules,
  and rule summaries never go there — they load with the body, for free, only when triggered.
- **SKILL.md body under ~500 lines**; the body is the procedure an agent runs, with detail in
  reference files **one level deep** (deeper nesting gets partially read). Any reference file
  over ~100 lines starts with a contents line so partial reads still see its scope.
- **A PROCEDURE skill keeps its lesson files one per PHASE of the procedure** (`dev-workflow`, and any
  skill that adopts the shape): one plain word each, listed in SKILL.md's phase table with a read-when
  line (the authoritative list is `dev-workflow/SKILL.md`'s phase table, conditional duty/post-PR files
  included) — no index file, no structured store; the bullet shape (bold rule, tag, a few lines) is the schema and the phase is the
  filter. Concern-organized skills (`dependency-updates`: gotchas / mechanics / learning) keep one concern
  per file as before. Caps are SOFT targets: SKILL.md 250 lines, each phase file 200 (Lin, 2026-10-01;
  25–150 per file before, board 30). Every line stays concise; at the cap, cut, or extract a concern to its own
  file — a battle-tested rule that must stay may run over (Lin, 2026-09-27). `lessons-lint.sh` carries
  dev-workflow's caps; a skill that adopts the shape points the lint at its own directory.
- **Keep inline what an agent needs on the spot to act** (gates, guardrails, the checklist) —
  never turn a load-bearing recipe into a lookup chain.
- **Deterministic steps are scripts in the skill's `scripts/` folder, pointed at from
  SKILL.md and EXECUTED, never re-derived** (Lin, 2026-09-08, `dependency-updates`): a
  script is a learning asset like every other file — one that fails or misleads is fixed
  in the same learning pass (`bash -n`, then re-run on the case that exposed it). Before the
  first push of a new or path-changed script, run it once FROM WHERE THE SKILL SAYS IT RUNS (a
  copied rig dir, a scratch clone), not from the repo, against its dry-run, a fixture or a
  disposable target when it would touch production: relative asset paths, dependency resolution
  and a profile dir landing inside the checkout only fail there (mkt PR#244). Prose keeps the
  judgment; the script keeps the mechanics. A skill's file/script layout is a
  seed, not a contract: add, merge, split, or delete as real work shows a better shape,
  judged on outcome, production risk, then efficiency.
- Checklists for multi-step procedures; ONE term per concept throughout; no time-sensitive
  phrasing ("before/after <date> do X" rots — provenance tags date a rule without expiring).
- When a file outgrows its size guidance, escalate in order (Lin, 2026-08-06): (1) tighten;
  (2) extract the concern to a reference file with a one-line WHEN-to-read pointer (one concern
  per file; in a procedure skill every file beside SKILL.md — a phase file or an extract of one — carries
  the 200-line SOFT cap above, other skills' reference files carry none); (3) still hard to place → ask Lin (attended)
  or file it on the owning desk/issue (unattended). **Never compress a load-bearing rule into
  ambiguity to satisfy a size target** (2026-08-06 lead-desk budget grind).

## The canonical configuration repo (Lin, 2026-10-06)

**`lz-networks/netpilot-skills` owns development-agent configuration for both Claude Code
and Codex:** shared skills at the repository root, project-specific skills/instructions/agent
scripts in `workspaces/<profile>/`, overrides in `workspaces/<profile>/overrides/`, and
personal skills in `personal/skills/`. The live checkout remains the workspace root’s
`.claude/skills/`; `~/agent-config` is a convenience link to it.

**Edit only canonical sources, never generated consumer files.** `.claude/agent-config.json`
in each consumer maps generated paths back to their source. `agent-config.json` in the
canonical repository owns profile selection; reference files and bundled scripts move with
their skill. Read [agent-configuration.md](../agent-configuration.md) before adding a profile,
changing discovery paths, or installing/syncing configuration. Provider caches, secrets,
application runtime bundles, and upstream repositories retain their existing owners.

**Ship duty:** use a branch in a scratch clone, PR + Codex review + checks, then merge per
`dev-workflow`; never switch the live source checkout’s branch. Pull the canonical checkout
with `git pull --ff-only`, run `sync-all.sh`, and ship generated changes through PRs in the
consumers. Sync refuses unrecorded edits rather than discarding them; move a verified local
change into its mapped source first. New personal skills use `scripts/agent-config.py personal`
to link the same folder into both hosts. Retired `signature-provisioning` is replaced by
`vm-onboarding` and `contract-onboarding` (Lin, 2026-09-16).

## Self-evolution charter (Lin, 2026-07-26; scope = every root skill, 2026-08-15)

- **Edit freely — no approval, no hold:** fact-based corrections — stale
  paths/commands/versions, wrong claims, typos, and new **verified gotchas** (a reproducible
  footgun with its provenance tag). Consolidating, tightening, extracting to reference files,
  and re-homing text per the placement rules is also self-serve. Note edits in your turn
  summary; that's transparency, not a gate.
- **Evidence-based policy amendments are ALSO self-serve** (Lin, 2026-08-22, granted on the
  PR#570 migration-ordering case): a policy edit — including one that qualifies or
  contradicts an existing rule — may ship without asking when it traces to CONCRETE
  evidence (a real observed event, PR, or incident, provenance-tagged in the edit) rather
  than judgment or preference. State the evidence in the edit itself and note it in the
  turn summary.
- **Ask Lin first:** policy changes WITHOUT concrete evidencing events — new constraints
  on agent behavior from judgment/preference, gate or autonomy-boundary expansions not
  forced by evidence — and creating/retiring a skill. **Evidence contradicting one of
  Lin's own explicit rulings is always a question, never a silent overwrite** (the
  supersession is his to make, however strong the data).
- When unsure which tier: it's a question.

**Every skill or workflow-doc edit also sweeps the touched file for stale lines and lands its rule
in as few lines as it takes** — re-read the whole file against its source of truth and fix what
drifted in the same PR; snapshots, one-off evidence (sizing counts, a run's numbers) and the STORY behind a rule go to the
PR or memory, never the skill — a tag, never the narrative; an evidence-based POLICY amendment still names
its evidencing event in ONE clause, as the charter requires, never the narrative (Lin, 2026-09-26: two skills carried a retired positioning line for
two days after the canonical doc changed). Every ~10 merges to a skill, run a prune pass — the earned-content tests applied to EXISTING lines
(`/Users/linzhu/agent-config/dev-workflow/scripts/lessons-lint.sh <worktree>/dev-workflow`
for dev-workflow); a skill that only grows is failing
(board 30, 2026-09-28). Before cutting, list the skill's commits from the last ~14 days: a rule that young has no
memory file yet, so it survives only as a bullet (PR #21 R1 dropped a two-day-old rule). After editing a section, re-scan its siblings and its SKILL.md
pointer for new duplication or drift before finishing.
