# Authority, delegation and merge boundaries

## Delegation modes (Lin, 2026-10-04 — two, nothing in between)

- **Default mode** (no explicit delegation): the agent handles low-risk PRs AND database
  migrations end to end — `agent/auto` work, plus migrations under the HOW rules in merge.md
  (additive applied to Neon before merge; destructive = expand → deploy → contract) — and leaves
  to Lin any PR that carries risk or a product decision: the never-auto list below minus
  migrations stays `agent/hold`. Migrations moved from never-auto to default-mode auto on
  2026-10-04 (Lin): an older migration issue still labeled `hold` is relabeled `auto` at pickup
  when its diff is a migration alone.
- **Full delegation** — Lin's words: *"if I say this, I expect the agent to make its own best
  decisions and handle everything end to end including merge PR, db migration, and all the
  other permissions that complete the task/project that I defined."* Every endpoint is
  merge-and-finish within the task/project he defined — guardrail surfaces, image promotion,
  fleet sweep, admin DB writes on the `db-access` allowlist included (off it stays a code change). Each PR body records it: `Delegation: full, Lin <date>,
  scope: <task/project>`. It still stops for what lies outside the defined task/project (a cross-phase
  scope move changes what he defined — `project-management`) and for what no mode covers: a reviewer outage, Stripe/billing amounts, anything irreversible outside
  the task. An `agent/stop` item inside the scope is worked: the agent takes the decision it was
  waiting for, records it on the issue (options + pick + why) and relabels before any code; a
  design or phase parent stays `stop` (worked via its sub-issues). Closing the BOARD stays his
  trigger (`project-management` Stage 2): the agent reaches closure-ready and asks once. The two
  gates and the HOW rules (migration ordering, the customer-VM script rule below, red-proofing)
  never lift.
- **An item inside a question just put to Lin waits for his answer, whatever its label**
  (Lin, 2026-10-02: "don't start work before I answer").

## Endpoints by label

- **`agent/auto`** — merge yourself after step 8, watch the deploy, clean up. At the round
  cap, merge-and-accept is legitimate when the residual fails its exposure test; drop to
  `agent/hold` only if the call genuinely needs Lin. Do not involve Lin unless something fails.
- **`agent/hold`** — stop at PR-ready (CI green + verdict on the CURRENT head + every finding
  dispositioned; a pending re-review is in-flight, not ready). Never enable auto-merge. Post:
  PR link, 2–4 line summary, exactly what Lin should test or eyeball, dismissed findings with
  one-line rationales. Merge only under full delegation or if Lin says so in the current
  conversation, then step 10–12; the base check applies with near certainty. **Feature builds
  and agent-behavior work under either grant — full delegation or a one-off merge say-so** (Lin, 2026-08-04): ship the product test WITH the feature in
  `NetPilot-2-Backend/tests/product/<feature>/` (PROMPT.md / VERIFY.md / probe; contract in its
  README — a judge agent grades behavior, never keyword matching), verify it yourself by RUNNING
  it (headless production turns: `probe-testing`), and hand Lin only an eyeball list plus the verified prompts. Then reconcile
  the run — HIS under a one-off grant, your OWN under full delegation — scorecard × VERIFY.md queries × UI claims — and feed
  every mismatch back into the feature before closing.
  Merges are delegated, `needs/screenshots` included (screenshots still attached as evidence).
- **`agent/stop`** — no worktree, branch, PR or code. Allowed: read-only investigation and one
  issue comment with 2–4 options and a recommendation. Code starts after Lin picks and tiers —
  or, under full delegation and inside its scope, after the agent's recorded decision (above).

## Duty flags

- `needs/drain-test` → kick off a long lab request just before the deploy, confirm the ~300 s
  drain lets it finish, verify `/health`.
- `needs/screenshots` → before/after frames + a click-through in the PR report
  (`screenshots.md`); never self-merged (it is `agent/hold`) except under either grant above — full delegation or
  Lin's one-off say-so.
- `p1 | p2 | p3` → sequencing only. Unblocked issues run in PARALLEL by default — several PRs in flight in one repo
  included (Lin, 2026-10-01, replaces "at most one `agent/auto` PR in flight per repo"; board 31's feedback lane). Only the
  MERGES queue: `merge.sh` holds the repo's merge slot until that merge's `postmerge.sh` ends clean, so a sibling's
  `merge.sh` answers NOT MERGED meanwhile and then meets step 8's base check (main moved → rebase + re-verify; merge.md).
  Two issues that edit the same file are not parallel (`project-management`'s parallel-lane analysis).
- A duty you cannot fully exercise: do the nearest verification and SAY so.

## Guardrails (always on — a diff can demote a label; a label never lifts these; the never-auto list opens only to the two carve-outs below, to Lin's one-off say-so in the current conversation, and to full delegation inside its scope)

- **Never-auto list — in default mode never self-merge a diff that touches:** auth
  (Clerk/JWT/JWKS/session/sign-out) · billing (Stripe/webhooks/tiers/cost recording/reconciler) ·
  VM lifecycle (Pulumi/GCP/Cloudflare/golden images/any destroy path) · anything in NetPilot-2-LB ·
  env or secrets · CI/workflow files · agent-governance files (`CLAUDE.md`, `AGENTS.md`, `.claude/`, `.agents/`,
  `DISALLOWED_TOOLS`) · a semver-major dependency upgrade · any Claude Agent SDK version change.
  DB migrations left this list on 2026-10-04 (Delegation modes). Diff-detected: demote yourself
  to `agent/hold` and name the class, even on a mislabeled issue.
- **A script that touches customer VMs or production data runs only from a reviewed, MERGED
  revision** (an urgent fix, or an additive/data migration applied before merge per merge.md: at
  least a Codex-clean head); a customer-VM or fleet script runs on the canary — Lin's own `linzhu-vm`
  — before the fleet (a migration's verification path is merge.md's, not a canary host) (Lin, 2026-10-04: the 0.3.36 sweep ran an unreviewed branch on 39 VMs; review
  then found 8 rounds of real edge cases, one of which had already stopped a VM mid-install —
  skills PR#59). Both modes.
- **Dependency-bump carve-out** (Lin, 2026-09-09): a diff that is ONLY a dependency bump on one
  of these surfaces follows `dependency-updates` tiers (T4 heavy gate merges; T5 holds).
- **Low-risk carve-out** (Lin, 2026-07-30): a guarded-surface diff may self-merge only when ALL
  FOUR hold — (1) risk ≤ 25 AND confidence ≥ 85 scored on the diff (15 until Lin, 2026-10-05: BE PR#969, a one-value
  retry-set fix scored 20, waited three days for his merge); (2) no semantic change to
  the guarded surface: observability-only lines, or a narrow pure-helper bug fix whose tests fail
  without it; (3) not hard-core — billing logic/amounts · env/secrets · CI/workflow files ·
  governance files (except the fact line below) · semver-major · Agent SDK are never self-merged
  in default mode, no scores; (4) CI + Codex clean, mandatory deploy watch, an FYI record naming
  the shape.
- **Fact-based CLAUDE.md line** (Lin, 2026-09-04): a repo or root CLAUDE.md line recording a
  verified fact or evidenced footgun may be written and self-merged. Collect them in ONE
  `agent/auto` docs issue per repo and land LAST as one PR; re-verify every collected line
  before landing by RUNNING what it claims, not only reading the code (2 of 3 needed correction, BE PR#748;
  4 of 6, three visible only in a run, clab PR#265), and grep the repo for `CLAUDE.md` pointers before
  renaming a section; state only the scope you
  verified — universal quantifiers ("never", "the only") are where every Codex precision finding
  lands (FE PR#536/#541, BE PR#842). Policy or preference changes to governance files stay Lin's in default mode.
- **Never self-merge a PR that weakens, skips or deletes tests/checks or lowers coverage** —
  automatic `agent/hold`, in both modes, unless that test change IS the defined task.
- Scope larger or different than the issue → `agent/hold` with the delta explained.
- Cross-repo work = one PR per repo, each under that repo's own issue label.
- Risk acceptance disposes of FINDINGS; it never moves a merge gate — not for a never-auto
  surface, not for CI-gaming, and never for a Codex outage (reviewer outages are always Lin's).
