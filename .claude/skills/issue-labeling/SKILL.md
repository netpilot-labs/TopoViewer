---
name: issue-labeling
description: NetPilot's GitHub issue label taxonomy and triage rules — what each agent/*, needs/*, and p1-p3 label MEANS, how to pick the right label when creating or triaging an issue or sub-issue, and how to sync the labels across repos. Use when creating, labeling, triaging, or breaking down any GitHub issue in a NetPilot repo, or to look up what a label means.
---

# GitHub Issue Labeling & Triage

Every NetPilot issue carries **exactly one `agent/*` autonomy label** (plus optional `needs/*` duty
flags, one `p*` priority, and — when the DevOps loop opened it — the `origin/devops` provenance tag).
The `agent/*` label is the per-issue signal that tells a future agent session how far it may take the
issue. This skill is the source of truth for **what the labels mean and how to
apply them**; the `dev-workflow` skill defines how each is executed.

## The taxonomy (9 labels, identical across all repos)

| Label | Color | Means |
|---|---|---|
| `agent/auto` 🟢 | `0e8a16` | An agent implements, gets CI+Codex clean, **merges itself**, and watches the deploy. Lin uninvolved. |
| `agent/hold` 🟡 | `fbca04` | An agent implements to **PR-ready** (CI+Codex clean) then stops; **Lin reviews/tests and merges** — or the agent does, under full delegation or Lin's one-off say-so in the current conversation (`dev-workflow` Delegation modes). |
| `agent/stop` 🔴 | `b60205` | **Do not start without Lin** — needs a decision, or isn't agent-suitable. Investigation + options only (under full delegation, in scope: the agent records the decision, then works it — `dev-workflow` Delegation modes). |
| `needs/drain-test` 🟣 | `5319e7` | Deploy must be validated with the mid-deploy ~300s drain test. |
| `needs/screenshots` 🟣 | `8250df` | Customer-visible — PR report needs before/after screenshots + a click-through. Implies `agent/hold`. |
| `p1` / `p2` / `p3` | `0052cc` / `2188ff` / `c5def5` | Priority / sequencing only — never changes autonomy. |
| `origin/devops` ⚪ | `ededed` | **Provenance, not autonomy** — the DevOps loop opened this issue/PR. Full semantics in the interpretation rules below. |

GitHub's stock labels (`bug`, `enhancement`, `documentation`, …) coexist on every repo and are fine as
plain type descriptors — they carry **no autonomy or priority meaning** and never substitute for the
`agent/*` label.

**Interpretation rules:**
- **Exactly one `agent/*` per issue.** If more than one, the most restrictive wins: `stop` > `hold` > `auto`.
- **Unlabeled** = `agent/hold` at most in an interactive session; for autonomous/cron pickup = `agent/stop`.
  Never infer `agent/auto` from issue content — only the label grants it.
- **Design principle:** labels carry only what an agent can't derive itself (Lin's merge trust,
  sequencing, unmissable duties). Safety-critical demotion is **not** a label — it's the always-on,
  diff-detected guardrails in the `dev-workflow` skill, so even a mislabeled issue can't self-merge a
  dangerous change.
- **`origin/devops` is a separate dimension** — *who opened it*, not *how far to take it*. The loop
  tags every issue/PR it opens; absence = human/attended. It **never gates action** (the `agent/*` lane
  is the sole action-gate, so a human-filed `agent/auto` ticket is still worked) — it governs *lifecycle
  deference*, and how the loop uses it (own-lifecycle vs defer-to-Lin) lives in the devops `CLAUDE.md`
  loop. **Under-tag rather than mis-tag:** wrongly tagging a human item makes the loop defer LESS, so
  tag only what the loop provably authored.

## PR labels — follow the owner; when mirroring, mirror exactly

**PR labels follow the OWNER** (rule owned by `dev-workflow` §flow): a **session-owned PR stays
UNLABELED** — labels on PRs are loop intake, and any hold is stated in the body; only a
**loop-owned PR mirrors** its issue's labels (2026-08-13: probe-lab PR#4 mislabeled then
corrected — the carve-out was stated only in dev-workflow). When mirroring: labels don't
propagate from an issue to its PR, so **mirror the issue's `agent/*` (+ any `needs/*`)
label onto the PR at creation** (`gh pr create --label ...`) — the *same* labels, not a separate PR
taxonomy. The concrete payoff: `gh pr list --label agent/hold` instantly answers "which PRs are waiting
for Lin to merge" vs `agent/auto` "self-merging". **When the loop opens the PR, add `origin/devops`** —
provenance follows the artifact's author: a loop-opened PR on a human-filed issue is `origin/devops`
(the loop owns driving that PR to ready), while the issue itself stays human-owned (Lin owns its
direction and closure). **Don't** add PR-status labels
(`needs-review`/`ready`/`wip`) — a PR's live state is already in its CI + Codex checks, so a parallel set
would rot and duplicate them. `p*` priority is optional on PRs (it orders the backlog, not open PRs).

**A label isn't applied until you read it back.** After creating any labeled issue or PR, verify with
`gh issue|pr view <n> --json labels` before recording the labels anywhere — a silently failed `--label`
orphans the artifact from every label query future sessions run (2026-08-02: FE PR#270 was recorded in
the devops worklog and desk as `agent/hold p3 origin/devops` but carried ZERO labels on GitHub, making
it invisible to the loop's resume step). Unattended devops passes additionally have a deterministic
backstop — a PostToolUse hook (`netpilot-devops/scripts/hooks/gh_create_labels.sh`) that auto-applies
`origin/devops`, mirrors the linked issue's labels onto loop-opened PRs, and fails loud into the pass
transcript when the `agent/*` label is missing; heed its feedback, but the read-back rule applies to
every session, hook or not.

**Bot-authored PRs (Renovate / Dependabot) that the dependency pass adopts get labels at
adoption** — `origin/devops` + the tier's `agent/<lane>` — the same intake semantics as a
loop-opened PR. An unlabeled bot PR is nobody's: BE#507 sat 22 days green and unreviewed
(Lin, 2026-09-09; mechanics in `dependency-updates`).

## Picking the autonomy label (triage)

- **`agent/auto`** — mechanical, low-blast-radius, well-scoped, touching **no** never-auto guardrail
  surface: patch/minor dep bumps, dev-gated tooling, docs, test-only additions, formatting — and, since
  2026-10-04, a DB migration (default mode handles it end to end under `dev-workflow`'s migration-ordering
  rules; it was `hold` before). CI+Codex are the real gate and the agent's deploy watch is the
  compensating control.
- **`agent/hold`** — anything an agent shouldn't merge unattended even if mechanically green:
  customer-visible UI/UX (add `needs/screenshots`), a change touching a **never-auto guardrail surface**
  (`dev-workflow` has the full list — auth, billing, VM/Pulumi, LB, env/secrets, major bump, SDK, CI
  files, governance files), a policy or config change, or anything that warrants Lin's eyeball or a
  product / cost / observability judgment. A "boring"-looking change can still be `hold` if its blast
  radius or a hidden interaction warrants review. The label is the DEFAULT-mode endpoint: under full
  delegation (`dev-workflow` Delegation modes) the agent merges `hold` items inside the defined scope.
- **`agent/stop`** — needs a decision *before* any code: new features, open-ended evaluations, design
  questions, autonomy-grant proposals, or work whose approach Lin must choose first. A parent issue —
  a design issue or a phase parent (`project-management` §board structure) — is `agent/stop` (agents
  work its sub-issues, not the parent). Under full delegation a `stop` item inside the defined scope
  gets its decision from the agent, recorded on the issue (`dev-workflow` Delegation modes).
- When torn between two, pick the **more restrictive** (hold over auto, stop over hold).

## Creating an issue (or sub-issue) with proper labels

- **Label at creation** — set exactly one `agent/*` (+ any `needs/*` + one `p*`) as you open the issue.
- **Sub-issues do NOT inherit parent labels** — label each one explicitly at creation.
- **Mid-project issues name their phase** — an issue created while a project board is
  running carries its phase (linking the parent phase issue) and an "In-phase because …"
  line, per `project-management` §Scope discipline. No phase, no filing: plan row or
  inherited-scope comment instead.
- **Write it agent-ready** — this, not the label, is what predicts merge success: one crisp deliverable,
  acceptance criteria, pointers to the files to change, no external-setup dependency. An issue that
  can't be written that way is `agent/stop` by definition.
- **Cross-repo:** a sub-issue may live in a different repo than its parent — create it in the repo whose
  code it changes, then attach it (implementation is still one PR per repo — see `dev-workflow`).
- Attach a sub-issue via GraphQL (local `gh` may predate native `--parent`; works cross-repo):
  ```bash
  gh api graphql -H "GraphQL-Features: sub_issues" \
    -f query='mutation($p:ID!,$c:ID!){addSubIssue(input:{issueId:$p,subIssueId:$c}){issue{number}}}' \
    -f p="<parent-node-id>" -f c="<child-node-id>"
  ```
  Get a node id with `gh issue view <n> -R <owner>/<repo> --json id -q .id`. Cap: 100 sub-issues/parent.

## Label creation & sync (the taxonomy is closed)

- **Agents never create, rename, or delete labels.** Only Lin changes the taxonomy.
- **NetPilot-2-Backend is canonical.** Propagate any change with
  `gh label clone lz-networks/NetPilot-2-Backend -R <owner>/<repo> --force`.
- `lz-networks` is a personal account (no Org Issue Types / default labels), so **every new
  agent-worked repo needs that clone command re-run at creation.** NetPilot-2-Scheduler has no GitHub
  repo — skip it.
