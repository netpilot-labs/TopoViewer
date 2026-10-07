# Mechanics — commands and scripts (low freedom: run these, do not re-derive them)

**Contents:** 1 Inventory · 2 Adopting a Renovate PR · 3 Provider-side change audit · 4 Lockfile
audit and red-PR diagnosis · 5 Dashboard checkboxes · 6 Surgical transitive bumps (uv /
pnpm) · 7 Trigger re-checks and alert dismissal · 8 Post-merge signals per repo · 9 The
revert and the platform rollback.

`O=lz-networks`. Repos: `NetPilot-2-Backend` (uv, Railway), `NetPilot-2-Frontend` (pnpm 10,
Vercel), `netpilot-marketing` (pnpm 11, Vercel), `containerlab-mcp` (uv, release-tagged),
`NetPilot-2-LB` (Dockerfile only, Railway).

**Scripts live in this skill's `scripts/` and are EXECUTED, not read** (each has `--help`
in its header; `bash -n` all of them after an edit). Invoke by ABSOLUTE path —
`<workspace>/.claude/skills/dependency-updates/scripts/<name>.sh` — this directory is
not your cwd inside a worktree (the `pr-gates.sh` trap, `dev-workflow`). A script that
fails or lies is a learning-pass item (learning.md rubric b): fix the script, not the
pass.

| Script | Does | Step |
|---|---|---|
| `inventory.sh [repo…]` | alerts + Renovate PRs (CI state) + dashboard sections per repo, with `FINDING:` lines for stale/red/conflicted items | 1 |
| `trigger.sh pypi-cap\|npm-cap\|patched\|resolvable …` | one-command trigger facts for blocked/dismissed rows | 2 |
| `lockdiff.sh <base> <branch> [--pr N --repo o/r] [--also <branch2>]` | moved packages LISTED/UNLISTED vs the PR table; shared moves between two branches | 4 |
| `release-age.sh pypi\|npm <pkg> <ver> [--security]` | age vs the 7-day cooldown; exit 1 blocks | 4, 6 |
| `resolved.sh <pkg>…` | the version(s) the lockfile in cwd actually resolved — the input to release-age and the audit, never the typed target | 4, 6 |
| `dashboard.sh <repo> show\|tick "<marker>"` | Dependency Dashboard checkboxes | 5 |
| `alert.sh <repo> show\|dismiss\|reopen …` | alert state changes with the reason/comment guards | 7 |
| `revert-pr.sh <repo> <pr> "<signal>"` | worktree + revert commit + non-draft PR + Codex request | 9 |
| `merge.sh <repo> <owner> <pr> [<worktree>] [--wait-codex]` | delegates gates/base/slot and squash-merge to canonical dev-workflow, then runs canonical postmerge for every repo; retains the worktree for authorized cleanup only after completion | 5 |
| `posthog-signal.sh [--window 15m]` | app capture still flowing after a deploy (HogQL count via the PostHog Query API; `POSTHOG_PERSONAL_API_KEY` scope `query:read` + `POSTHOG_PROJECT_ID` + `POSTHOG_HOST` in netpilot-devops/.env, copied from the lead desk 2026-09-10 — the frontend's phc_ token is write-only); exit 1 = REVIEW, 2 = not configured | 8 |
| `<skills>/dev-workflow/scripts/postmerge.sh <repo> <merge-sha>` (moved there, board 30) | the §8 signals executed: deploy success (Railway/Vercel), health or route load, backend `main` run, Sentry new groups; exit 1 = RED (impact decides, `dev-workflow/deploy.md`) | 5, 8 |

## 1. Inventory

Run `scripts/inventory.sh` (all five repos by default). Read every `FINDING:` line into
the pass; each one is either an item to tier or a ledger row to write.

- `-> NONE` = no patched version → ladder step 4. `[development]` scope = dev-only exposure
  candidate — still verify by grep: a dev dep can be imported at runtime (marketing's
  `date-fns` was misfiled, `renovate-fleet-policy`).
- Alert lists can lag merges by a scan cycle — verify against the lockfile on `main`
  before counting an alert as open (gotchas.md §4). Observed the other way
  too: #30 and #77 flipped to `fixed` 3–4 min after their merges (pass 1, 2026-09-09).
- "dashboard: none open" on a repo that has Renovate = the issue was closed; reopen it
  (gotchas §1).

## 2. Adopting a Renovate PR

Renovate PRs are non-draft, so CI already ran on open; Codex has NOT — bot PRs get no
automatic review (BE#507 sat 22 days with zero reviews).

```bash
gh pr edit $N --repo $O/$R --add-label origin/devops --add-label agent/<auto|hold>   # adoption labels (ratified 2026-09-09)
env -u GH_TOKEN -u GITHUB_TOKEN gh pr comment $N --repo $O/$R --body "@codex review"
<skills>/dev-workflow/scripts/pr-gates.sh $N --repo $O/$R --watch          # the Codex half
t=$(date -u +%Y-%m-%dT%H:%M:%SZ); gh pr ready $N --repo $O/$R          # hand PRs only; Renovate PRs are already non-draft
<skills>/dev-workflow/scripts/ci-wait.sh $N --repo $O/$R --since "$t"       # the CI half, then pr-gates again
```

The same `ci-wait.sh --since` runs after a close/reopen re-verify when main moved under
the PR (first pass, FE#482, 2026-09-09: main advanced 2.5 min after the green run was
created, so the merge-commit carve-out did not apply).

- Rebase through the dashboard, not by pushing over Renovate's branch:
  `scripts/dashboard.sh $R tick "rebase-branch=renovate/<slug>"`. A hand commit on the
  branch marks the PR "renovate-edited" and stops future rebases — fine when driving to
  merge this pass, wrong when parking it.
  **The tick rebases within ~minutes** (Renovate reacts to the checkbox, force-pushes a
  fresh head, CI re-runs) — so a stale window-batch PR whose head CI predates the current
  main tip (merge-commit carve-out fails) can be **rebased → re-Codex on the NEW head → merged
  IN THE SAME PASS**; don't reflexively defer it to next pass. Re-request Codex on the new
  head (the pre-rebase request is void). Provenance: pass-688 (2026-09-14) ticked BE#776 +
  FE#525, both rebased + merged clean ~10 min later, inside the Monday window. (And every
  merge in a repo re-stales the OTHER open PRs there — the next one needs its own rebase tick.)
- Merge with `scripts/merge.sh`: it delegates to canonical dev-workflow's merge gates,
  base proof and slot, then runs canonical postmerge for EVERY repo, including required
  main-push CI on no-deploy repos. A failed or pending watch returns nonzero; retain the
  worktree until completion and authorized cleanup. After a non-clean watch, the next
  merge uses `MERGE_SLOT_ACK=<that pr>` only once its result is dispositioned
  (`dev-workflow/merge.md`). No bare `gh pr merge`; if the wrapper cannot run, use
  dev-workflow's `merge.sh <o/r> <pr>` and its required postmerge completion.
- **Sibling lockfile PRs in one repo are rebuilt, never textually merged**: after any merge
  that touched the lockfile, the next PR is reset onto `main`, its edits re-applied, relocked,
  `pnpm install --frozen-lockfile` verified on that tree, and its re-verify run minted ≥2 min
  after the sibling merge (FE#489 → broken lock on main → Vercel red → revert, 2026-09-09).
- **The same applies to Renovate's own branches**: a green Renovate PR whose base predates the
  last lockfile merge on `main` is superseded by a hand PR on current `main`, not merged
  (`scripts/lockdiff.sh origin/main origin/<branch>` showing tonight's bumps as "moved
  backwards" is the tell — FE#430/#336, 2026-09-09). Renovate's PR auto-closes when the alert
  clears; the pass comments the supersession on it first.
- **Held T5 PRs go stale the same way**: every hand PR held on a decision is refreshed at the END of
  the pass, after the last self-merge — pnpm lockfiles rebuilt (reset + reapply + relock +
  gates), uv lockfiles rebased then `uv lock --check` (independent package blocks merge
  cleanly; the check proves it), CI re-minted on the new head, a one-line "rebuilt on main"
  comment posted. Otherwise his click lands a CONFLICTING or untested merge ref (FE#486 went
  CONFLICTING after #494; MKT#176 and BE#744 were untested against main, 2026-09-09).

## 3. Provider-side change audit (every T2/T3/T4 item; the whole job for a major)

The audit answers three questions in order — what the provider changed, whether any of it
lands on a code path we use, and what OUR code must change alongside the bump — and it is
verified by running, never by reading alone. Provenance: the Stripe 14→15 walk (BE#371,
2026-08-03/04) — the prior attempt shipped a bump whose breaking change was not an API
rename but an OBJECT-SEMANTICS change (`StripeObject` lost dict inheritance: `.get()` /
`.items()` raise on live objects), and production billing failed as "paid but plan not
upgraded". The successful walk probed the new SDK first, normalized every boundary in the
same PR, and watched the first organic payment.

1. **What changed, from the provider.** Non-major: the release notes Renovate puts in the
   PR body (Changed / Removed / Breaking / Deprecated between the two versions). Major, or
   ANY billing/auth/server-stack lib at any bump: the upstream CHANGELOG for every version
   between ours and the target, the migration/upgrade guide, deprecation notices, and the
   API-version semantics — an SDK bump can move the version used for DIRECT calls while a
   webhook endpoint stays pinned on the provider's side (Stripe: pin `stripe.api_version`
   explicitly; payload drift was NOT the v15 risk, object semantics were).
2. **Map our usage.** Every import, every call site, and every ACCESS PATTERN on returned
   objects (attribute vs dict, iteration, `.get`), not just the function names:
   ```bash
   grep -rn -E "^(from|import) <pkg>" app/ tests/ --include='*.py' | cut -d: -f1 | sort -u
   grep -rn -E "from ['\"]<pkg>(/|['\"])" --include='*.ts' --include='*.tsx' app lib components | cut -d: -f1 | sort -u
   ```
   Start from the ledger's audit notes for the package; end by updating them.
3. **Probe, never assume** (a major, or any changelog line that touches step 2): install the
   target in a scratch venv / worktree and exercise the exact object shapes we touch
   (`probe-testing`'s cheapest tier — code, then a scratch run). The v15 probe found deep
   `to_dict()` sufficient and `stripe.error` still aliased; that decided the PR's shape.
4. **Adapt our code in the SAME PR as the bump**: boundary helpers or normalization, plus a
   compat test double that fails on the OLD behavior (red-proven — `dev-workflow/test.md`) and the surface's own verification: billing → a real HMAC-signed `construct_event`
   test and a test-mode or organic purchase on the new code; auth → the real-Clerk suite;
   server stack → the drain test; frontend framework → `next build` locally.
5. **Post-merge business signal per surface** (mechanics §8 has the platform signals):
   billing → `billing_state_reconciler` alerts and the first organic payment reconciled in
   Neon (the "paid but not upgraded" fingerprint is a `users` row whose tier lags a paid
   invoice); cost → `cost_reconciler_deploy_check`; auth → the `main` run's real-Clerk job.
6. **Write the verdict on the PR**: `Audit: <pkg> a→b — read <sections/guide>; touches
   <call sites or none>; probed <what>; adapted <what>; signal <what to watch>`. Codex
   reviews that line; the ledger abbreviates it.

A major on a T4 surface is the pass's merge once steps 1–5 are done and the surface check
(tiers §2) passes; a T5 decision test firing is the only stop. A non-major whose step 1
shows nothing on our paths is done at step 6.

## 4. Lockfile audit and red-PR diagnosis (every PR; the whole diagnosis for a red T1 PR)

```bash
cd <repo checkout> && git fetch origin main renovate/<slug> [renovate/<slug2>]
scripts/lockdiff.sh origin/main origin/renovate/<slug> --pr $N --repo $O/$R [--also origin/renovate/<slug2>]
# refs only: on a hand lane COMMIT first, then `lockdiff.sh origin/main HEAD` — before the
# commit HEAD == main and "0 added/changed, 0 removed" is main compared to itself, not an
# audit (posthog lane, 2026-09-09)
```

- Every `UNLISTED` line is a transitive the branch re-resolved inside ranges. For a red
  PR the `shared moves` block (two sibling red branches) is the suspect list
  (FE#337/#338, 2026-09-08).
- Release age for hand-made bumps (SKILL.md always-on): `scripts/release-age.sh pypi|npm
  <pkg> <ver>`; exit 1 = wait, unless `--security`.
- Bisect by pinning suspects back one at a time in a scratch worktree (`pnpm.overrides`
  / `uv lock --upgrade-package pkg==old`), running ONE failing suite, never the whole run.
  **Cap: 3 repair attempts** on a red PR, then supersede with the clean subset or hold
  with the findings (the cap is Google's dependency-director default, research
  2026-09-08). Report the culprit on the PR.

## 5. Dashboard checkboxes

`scripts/dashboard.sh $R show` lists sections and unchecked markers;
`scripts/dashboard.sh $R tick "<marker>"` ticks one (`approve-branch=…`, `manual job`,
`rebase-branch=…`, `rebase-all-open-prs`, `unschedule-branch=…`). Renovate reacts within
minutes on the Mend-hosted app. Approval opens a PR; it never merges one. Never close the
dashboard issue.

## 6. Surgical transitive bumps

The rule: a targeted override + a lockfile-only install, never a whole-graph re-resolve (any
`pnpm update` form = 12k-line churn, FE PR#205); range-scope (`pkg@<patched`) when several majors
coexist. These are the commands per manager, run in a fresh worktree (`dev-workflow` flow):

```bash
# uv (Backend, containerlab-mcp): move ONE package, keep everything else
scripts/trigger.sh resolvable <pkg>          # dry-run plan; "BLOCKED" = a cap → ladder step 3
uv lock --upgrade-package <pkg>              # or <pkg>==<ver>
uv sync --all-groups && git diff --stat uv.lock
# pnpm 10 (Frontend): pnpm.overrides in package.json;  pnpm 11 (marketing): overrides: in pnpm-workspace.yaml
pnpm install --lockfile-only && git diff --stat pnpm-lock.yaml
```

- Range-scope pnpm override keys when multiple majors coexist; refresh an existing key
  in place rather than stacking a new one per advisory (FE overrides are consolidated —
  `renovate-fleet-policy`, FE PR#308).
- A peer dependency ignores overrides — add the package as a root devDependency instead
  (`dependabot-fleet-zero`, marketing esbuild).
- **Read the RESOLVED version from the lock after the relock, then `scripts/release-age.sh`
  on THAT** — a caret override (`^4.3.1`) resolves the newest in-range release, not the
  alert's patched version (FE#482, 2026-09-08: alert said 4.3.1, the lock landed 4.3.2;
  the gate must be `resolved >= patched`, and the cooldown applies to the resolved one).
  `scripts/resolved.sh <pkg>…` prints them (pnpm or uv lock in cwd); pin a package exact
  when the caret resolved past the audited version (runtime-a lane, 2026-09-09: posthog-js
  1.428.7 resolved for an audit of 1.424.1).

## 7. Trigger re-checks and alert dismissal

Trigger shapes the ledger uses, one command each:

```bash
scripts/trigger.sh pypi-cap <capper> <pkg>     # "a release of <capper> that allows <pkg> >= <fixed>"
scripts/trigger.sh npm-cap  <capper> <pkg>
scripts/trigger.sh patched  $R <alert-n>       # "a patched version of <pkg> exists"
npm view <framework>@<our-ver> dependencies --json | jq '.["<pkg>"]'   # "the framework's own range admits the fix" (never override past it)
```

State changes (reversible; nothing in prod moves):

```bash
scripts/alert.sh $R show <n>
scripts/alert.sh $R dismiss <n> not_used "<evidence — build-time only / API unused (grep) / dev tool not executed>; re-check: <trigger>"
scripts/alert.sh $R reopen <n>
```

The script refuses `no_bandwidth` (the state this skill exists to remove) and comments
over GitHub's 280-char cap. `tolerable_risk` on a runtime-reachable path is Lin's
(tiers.md §6.4). `fix_started` fits a cap-blocked alert whose upstream fix is in flight —
with the trigger in the comment.

## 8. Post-merge signals per repo (read ALL before the next merge in that repo)

Run `<skills>/dev-workflow/scripts/postmerge.sh $R <full merge sha>` — it executes this table and exits 1 on a
RED deterministic signal, naming which one in its `RESULT` line (the impact rule in `dev-workflow/deploy.md` decides roll
back vs fix forward); Sentry groups it prints are for the pass to attribute.

| Repo | Deploy watch (`dev-workflow/deploy.md`) | Then read |
|---|---|---|
| Backend | Railway rollout + `/health` 200 | the `main` push run's **API Integration Tests (Real Clerk Auth)** job — it runs on `main` only (no `workflow_dispatch` trigger exists), so it is the FIRST time an auth-touching dep is exercised by CI; red → §9. Sentry backend: no new issue groups in +60 min. Scheduler service restarted clean (same image) |
| Frontend / Marketing | Vercel deployment `success` + one route load (`/sign-in` for app, `/` for marketing). The app's `version.json` carries `version` (sha — what this watch reads) and `assetHash` (what the refresh toast reads; identical across deploys that ship the same client code, FE PR#497) | Sentry frontend: no new groups +60 min; `scripts/posthog-signal.sh` (HogQL event count over the last 15 min; runs inside `postmerge.sh`; live since 2026-09-10) |
| containerlab-mcp | no deployment on merge — ships with the next tagged release (`golden-image` owns the fleet) | required main-push workflows and named jobs complete successfully before the next merge |
| LB | Railway (a tag bump IS the deploy; T4 — `haproxy -c` in the new image first, in the window) | CORS preflight (deploy.md, CORS) + sticky-cookie sanity, immediately; revert = previous tag |

Server-stack bumps on the backend (`uvicorn`, `fastapi`, `starlette`, `sse-starlette`,
`h11`, `httptools`, `websockets`, `anyio`) carry `needs/drain-test`. Headless nearest
verification: hold one `GET /api/v1/chat/subscribe/<session>` SSE stream open across the
rollout and confirm it ends cleanly (keepalives until the drain, then reconnect) — say
explicitly that the full lab-request drain test was not run.

## 9. The revert and the platform rollback

Use it when the impact rule says roll back (`dev-workflow/deploy.md`: production unavailable or many users hit), or when
the pass picks a revert as the forward fix for a red its bump caused. A dep bump never carries a migration, so it is always
cleanly revertible:

```bash
scripts/revert-pr.sh $R $N "<signal that fired, with link>"     # worktree + revert commit + PR + @codex review
```

Then `pr-gates.sh`, self-merge it (auto-revert grant, tiers.md §5), deploy watch again,
incident row in the ledger, package onto the watch list, the signal that caught it
recorded in §8 if it is new.

**Emergency stop while the revert lands:** Railway one-click rollback of the service
deployment (restores image + variables) or Vercel Instant Rollback — both leave `main`
broken, so the revert PR is mandatory either way; the rollback only buys the minutes.
