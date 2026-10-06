# Managing shared agent configuration

## Authoring

Open `/Users/linzhu/agent-config`, which links to the existing canonical checkout. Change shared
skills at the root, project instructions and variants under `workspaces/<profile>/`, and personal
skills under `personal/skills/`. Keep each skill’s `SKILL.md`, references, scripts and assets
together. Profile-specific variants remain distinct even when their skill names match.

`agent-config.json` selects each profile’s source directories and optional override blocks.
Each generated consumer’s `.claude/agent-config.json` records source paths and deployed hashes.
Use that mapping to locate the owning file; generated files are installation outputs, not a
second authoring location. Project application code stays in its product repository.

## Shipping

Follow `dev-workflow` using a scratch clone of this repository. After review/checks and merge,
pull the live source checkout and run `sync-all.sh`. Each changed consumer receives its own
reviewed PR; its checked-in snapshot works on another machine or in a worktree without the
canonical checkout. Local setup does not commit, change branches, merge, or push anything.

`sync.sh <consumer-root>` retains the existing caller interface, including `netpilot-dev`’s
wrapper. Profile inference uses installed metadata or the Git origin, so a worktree’s branch
folder name does not select the wrong profile. Pass `--profile` to the Python CLI for an
explicit selection. Exit 0 means current; 10 means changes/drift; 2 means a conflict or invalid
configuration. `--check` never writes.

## Local edits and recovery

Sync compares existing files with the last deployed hashes before changing anything. A local
edit/deletion or an unknown conflicting discovery entry stops the plan. Move the intended edit
into its mapped source and review it there; preserve unrelated work. Initial adoption accepts
only the original inventoried content or the desired generated content. Previously managed
files removed from the source are pruned only while unchanged. Unowned files stay in place.

The local installer backs up replaced instruction/configuration/helper files under
`~/.local/share/agent-skills-backups/`. Existing provider-managed caches are not imported,
renamed or rewritten. Never commit ignored `.env` files from a live skill directory.

## Personal skills

Create `personal/skills/<name>/SKILL.md` and its resources here. Run
`~/.local/bin/link-agent-skills` (the installed wrapper for `scripts/agent-config.py personal`)
to link the same skill folder into `~/.claude/skills` and `~/.agents/skills`. Existing name
conflicts are reported before installation. Tool-specific capabilities still use the tool’s
own plugin; sharing a skill does not rename SDKs, APIs, commands or tool identifiers.

## Verification

Run `python3 -m unittest discover -s tests`, syntax-check tracked shell/Python scripts, and
run `dev-workflow/scripts/lessons-lint.sh <clone>/dev-workflow` when that skill changes. Check
`sync --check` from consumer snapshots. For discovery changes, verify fresh local host loaders:
Codex app-server `skills/list`, and Claude Code’s initialization command catalogue; these need
no model turn or production-agent probe. Runtime product prompt changes use `probe-testing`.
