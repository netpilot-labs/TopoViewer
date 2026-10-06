# Tiers — the policy core (Lin owns the boundaries)

**Contents:** 1 Tier table with gates and endpoints · 2 Which items are T4 · 3 Grouped
PRs · 4 Trust rules the ledger enforces · 5 Dashboard items · 6 Lines awaiting Lin's
ratification.

Seeded 2026-09-08 from the fleet's live Renovate config (7-day `minimumReleaseAge`,
`low-risk-dev` automerge tier, approval-gated high-risk deps; `renovate-fleet-policy`,
2026-08-05) and `dev-workflow`'s guardrails. Changing a tier's endpoint is an autonomy
change — Lin's, always (`skill-maintenance` charter).

## 1. Tier table

| Tier | Definition | Gates (all required) | Endpoint |
|---|---|---|---|
| **T0 security** | Renovate `[SECURITY]` PR; an open Dependabot alert whose patched version resolves | The underlying package's tier gates. Cooldown waived (config). | First in the pass. Endpoint = the package's tier. A fix that needs a MAJOR of a direct dep = T4 with the safety verdict already written |
| **T1 dev/build** | The `low-risk-dev` Renovate group: non-major bumps of dev/test/lint/type packages, non-0.x | CI green (Renovate waits for it itself; `platformAutomerge: false`) | Renovate automerges when a run lands in its `automergeSchedule` (Friday 21:00–Saturday 03:00 ET, before the loop's window) on a green head — a miss is routine, since every merge on `main` makes Renovate rebase it and restart CI (FE#566, 2026-09-29; Lin). So a green T1 PR still open when the window pass reaches it is **the pass's merge**: adopt (mechanics §2), `merge.sh`, **first** in its repo's order. RED → diagnose (mechanics §4), fix-forward on the Renovate branch (≤3 repair attempts), or supersede with a hand PR of the clean subset |
| **T2 runtime patch** | Runtime dep, patch bump | Changelog audit clean for the code paths we use (mechanics §3) · lockfile diff audited (§4) · Codex dispositioned · CI green (`pr-gates.sh`) | Self-merge → deploy watch → post-merge signals → on red, impact decides (`dev-workflow/deploy.md`) |
| **T3 runtime minor** | Runtime dep, minor bump | T2 gates **and** package not on the ledger watch list **and** no "Changed/Removed" changelog line lands on a used code path | Self-merge as T2. A gate short (a Changed line on a used path) → the pass's call, not a hold (Lin's standing grant, 2026-09-09): split the flagged members into their own PR with an explicit post-deploy verification per member, merge it separately so a revert is targeted. A watched package is never a hold either (Lin, 2026-09-09 12:40Z): its own PR, the ledger's watch signal verified post-deploy, the extended watch of §2 |
| **T4 heavy-gate** | §2 below — the surfaces `dev-workflow` never self-merges for feature work. For a DEPENDENCY bump they are the pass's to merge under the heavier gate (Lin, 2026-09-09 12:40Z; §6) | T2 gates, plus mechanics §3 in full (for a major: adaptation in the same PR with a red-proven test), plus the surface's own check (§2), plus the extended watch (§2) — a dev-only major takes §3 step 1 + CI + Codex, no probe or extended watch (§2) | Self-merge end to end. Inside T4 the risk split of §2 applies: a bug-fix patch/minor of a T4 package is handled as T2/T3 with the surface check appended — "just do it" |
| **T5 decision** | §2 "Lin's line" — a real decision or an irreversible step, never a click | T4 gates, worked to **PR-ready** (CI green, Codex dispositioned, the surface check run, the PR refreshed onto current `main`) wherever a PR is the artifact | One desk line stating the decision, the recommendation and the PR link; the pass holds the merge until Lin answers, then merges and watches it like any T4. Where no PR makes sense (a Renovate approval box, a Pulumi replace shown by `preview`), the desk line carries the options. A major break is reported as an incident (ledger + desk), not held |

"Audit clean" is a judgment with a written line: which changelog sections were read,
which of our imports they touch, why it is safe. The line goes on the PR (Codex reads it)
and, abbreviated, into the ledger's audit notes for the package — that is how the next
audit starts ahead.

## 2. Which dependency items are T4 — and the risk split inside it

The list is `dev-workflow`'s never-auto surface applied to dependencies. For a dependency
bump these are **the pass's merges** (Lin, 2026-09-09 12:40Z: "even for T4 we should be
treated separately based on the risk … I'll be only involved if there is any major break or
any decision you really need me, not to verify production and click merges"). What the tier
adds is a heavier gate, a surface check, and a longer watch — never a hold.

**Risk split (applies before anything else):**
- **Bug-fix patch or minor** of a T4-listed package (changelog: fixes only; no
  Changed/Removed/Deprecated line on a path we use) → T2/T3 handling, with the surface check
  below appended. Just do it.
- **Major, or a minor with a Changed line on a used path** → mechanics §3 in full
  (upstream changelog → our access patterns → probe in a scratch venv → adaptation in the
  SAME PR with a red-proven compat test) → surface check → self-merge → extended watch.
  A dev-only major (below) stops after §3 step 1: no probe, no extended watch.
- **T5** only when the decision test at the end of this section fires.

**Surfaces and their own check** (run before merge; the post-deploy probe joins the watch):

- **Semver-major** of anything (a dev dep too — clerk-backend-api 6→7 was one): §3 in full.
  **Dev-only semver-major** (Lin, 2026-10-05: "yes, totally agree") — a major of a package that ships nothing
  (devDependencies / the `dev` or `test` group: lint, types, test runners, build plugins — confirmed by the
  runtime-import grep of mechanics §1, since a misfiled dev dep can be imported at runtime) merges on CI green +
  Codex clean after §3 step 1 in full (every intervening changelog, the migration guide, deprecation notices —
  nothing on a path our config, build or tests use); it waives only the generic scratch probe and the extended
  watch. A surface listed below that also matches (an approval-gated group such as `typescript` / `eslint-core` /
  `ruff` / `mypy`, a CI action) keeps that surface's own check. The gate is lighter, the merge ORDER is not: a dev
  package whose major can change the built output (a bundler, compiler or build plugin) takes the repo's
  runtime-affecting merge slot (SKILL.md Always-on), so a signal in the ride-out still names one PR. FE#590/#592
  (jest-dom 7, globals 17) sat parked a week as "a Lin walk" under the old reading.
- **`claude-agent-sdk`** and its coupled `mcp` pin → hand to `sdk-upgrade-adoption`. The
  DevOps loop does NOT run that walk (probes, a board, product gaps for Lin); unattended,
  the hand-off is a desk line "SDK x.y.z available — run `sdk-upgrade-adoption`" on
  `REVIEW.md`, and Lin or a session starts it (verified 2026-09-11: not in the loop's hook).
- **CI/workflow files** — every `actions/*`, `astral-sh/setup-uv`, `pnpm/action-setup` bump
  edits `.github/workflows/`. Check: the PR's own run green **and** the `main` push run green
  after merge (the only place some jobs execute). Cannot touch production; a red main run is
  fixed forward or reverted the same pass.
- **Auth libs** — `clerk-backend-api`, `@clerk/nextjs`, `PyJWT`, `cryptography` when it is
  the auth path's crypto (grep the import). Check: real-Clerk suite locally (gotchas §3
  recipe) before merge; post-deploy: the `main` run's real-Clerk job green (it IS the
  authenticated call, with a real Clerk JWT) + `/sign-in` 200 + Railway logs since the
  deploy show authenticated `/api/v1/*` traffic answering 200 with no 401/500 wave and no
  jwt/jwks error lines (`railway logs --tail 300`; BE#744 probe, 2026-09-09).
- **Billing libs** — `stripe`, `svix` (Clerk webhook signature verification gates org/seat
  events), `@paypal/*`. Check: §3 against every webhook handler and every object shape we
  read (the Stripe 14→15 incident: paid but plan not upgraded); post-deploy: the next
  webhook delivery returns 200 in Railway logs and the handler's business row lands
  (subscription/tier updated) — watch until one real event has passed, or fire a test-mode
  event.
- **Runtime images and pins** — `python`, `node` (Dockerfile, compose, CI services,
  `.python-version`): CI + build on the new image. `postgres`: must equal Neon's major —
  changing the major is T5. `packageManager` (pnpm): exact pin + `--frozen-lockfile` install.
- **Pulumi providers** — `pulumi`, `pulumi-gcp`, `pulumi-cloudflare`: `pulumi preview`
  against ONE live user stack. No diff, or update-in-place only → merge. Any replace/delete →
  T5 (live user VMs; not revertible by redeploy). Record the shape in mechanics §8 the first
  time it runs.
- **NetPilot-2-LB** — a `haproxy` tag bump IS the deploy. Check: `haproxy -c -f haproxy.cfg`
  inside the new image; merge in the window; probe CORS preflight + sticky cookie
  (mechanics §8) immediately, revert = redeploy the previous tag.
- **Approval-gated groups in the Renovate configs** — BE `ruff`/`mypy` (new lint rules
  redden CI), FE `nextjs-core` / `react-core` / `assistant-ui` / `eslint-core` /
  `typescript`, marketing `contentlayer` pair. Ticking the approval box opens the PR; the
  pass walks it with the full suite + build + the framework's post-deploy probes.

**Extended watch for every T4 merge:** `postmerge.sh` + the 60-minute Sentry sweep + the
surface's post-deploy probe above + a ledger watch row that the next pass re-checks (24 h
signal: Sentry new groups, the business row for billing, sign-in for auth).

**Lin's line — the T5 decision test (any ONE fires):**
1. A product or policy choice is embedded: which Postgres major to run, enabling a
   dispatch on a protected environment, Stripe product/price objects, an adaptation that
   changes what users see.
2. An irreversible or data-affecting step: a destructive migration, a Pulumi replace/delete
   on live VMs, anything a redeploy of the previous sha cannot undo.
3. The changed behavior sits on money, auth, or user data AND no test, probe, fixture or
   replay the pass owns can verify it before merge — the pass builds the fixture first when
   it can; only when it cannot is this T5.
4. A major break happened: an incident report on the desk with the revert already done,
   never a click.

## 3. Grouped PRs

- A grouped PR's tier is its **highest member's**. `group:allNonMajor` mixes T2 and T3
  runtime deps in one window PR; the whole PR is T3.
- A member fails its audit → do not hold the whole group hostage: open a hand PR with
  the clean subset (same branch base, `dev-workflow` flow) and let Renovate re-group
  the remainder after main moves. Record the flagged member on the watch list with the
  reason.
- A member that is `claude-agent-sdk`, or any T4 item, is split out first (SKILL.md
  always-on rules).

## 4. Trust rules the ledger enforces

- **Watch list (demotion — automatic, self-serve, evidence-based):** a package whose
  bump caused a revert, a red post-merge signal, or a documented behavior change on a
  used path goes on the watch list with the incident pointer. While listed, its T3
  bumps hold; its T2 bumps still self-merge but with the incident's signal re-read
  post-merge. Leaves the list after **3 consecutive clean merges** (recorded in the
  trust table).
- **Promotion (never self-granted):** the ledger counts clean merges per package; when a
  held package or a whole tier boundary shows ≥3 holds that Lin merged unchanged, the
  learning pass files a **proposal** row (evidence count + link list). Lin's reply moves
  the boundary; the pass never does.
- **Counts are per package per repo.** A clean merge = merged, deploy watch closed, post-
  merge signals clean, no revert within 7 days.

## 5. Dashboard items

- **Pending Approval — the pass ticks the SAFE entries itself, on every pass (SKILL.md step 2)** (Lin,
  2026-09-29: "i don't want to handle any such safe low risk items"): a **patch or minor**
  of an approval-gated group whose current version is **≥1.0**. Renovate opens the PR
  within minutes, outside its `schedule` (FE #570–#573, 2026-09-29), so it is green by
  the window, where it is walked as §2's bug-fix split (T2/T3 + the surface check) and
  merged. A tick only opens a PR, so the T5 test runs at that walk, not at the tick — a PR
  it fires on is held per T5's endpoint. Ticks never starve T0: Renovate counts security
  branches/PRs separately (`Vulnerability*` limits, `lib/workers/global/limits.ts`) and
  lets ticked branches past the branch limit (FE #570–#574 = 5 PRs at limit 3).
  **Not auto-ticked:** majors, 0.x minors (breaking by semver — `assistant-ui`),
  `claude-agent-sdk` (hand-off) — for those, tick only when walking the item this pass;
  the verdict must exist before the box does.
- **Awaiting Schedule** — leave; Renovate opens it Friday night (fleet `schedule`).
- **Rate-limited / prConcurrentLimit** — the fleet config caps open PRs at 3; a stale open
  PR starves the queue. Draining is the fix, never raising the limit.
- **Runtime image majors** — `postgres` follows Neon's major (`db.sh ro "SELECT
  version();"`; 17.x on 2026-09-08): CI/compose never ahead of prod. `python`/`node`
  majors follow the Dockerfile/Vercel runtime; verdict + Lin.
- **Dismissal authority** (ratified 2026-09-09): `not_used` for dev/build-only exposure is
  the pass's call; any runtime-reachable dismissal (`tolerable_risk`) is Lin's.
- **Auto-revert grant** (ratified 2026-09-09): the pass self-merges a revert of ITS OWN
  dependency merge, then reports; it never waits to ask. WHEN to use it is the impact rule
  (Lin, 2026-10-01, `dev-workflow/deploy.md`): production unavailable or many users hit →
  revert now; anything smaller is worked forward — a revert is then one of the fixes the pass
  may choose when the bump is the cause, never the reflex to a red signal.

## 6. Decisions ledger (ratified 2026-09-09 — Lin: "go with your recommendations")

Provenance only; the operative rules live in §1–§5, SKILL.md, and mechanics.
**Standing grant (Lin, 2026-09-09 03:40Z):** every tier below T4 is delegated end to end —
merges, code changes, migrations included. **Superseded 12:40Z the same day:** "even for T4 we
should be treated separately based on the risk, if just a minor bug fix version, you should just
do it, i'll be only involved if there is any major break or any decision you really need me, not
to verify production and click merges, that is something you own and can handle end to end" —
T4 became heavy-gate self-merge with the §2 risk split; T5 (decision test) is the only hold.
P1 T3 self-merge when audit clean and not watched (§1) · P2 auto-revert grant (§5, mechanics
§9) · P3 adopted bot PRs get `origin/devops` + `agent/<lane>` (mechanics §2; `issue-labeling`)
· P4 dismissal authority (§5) · P5 Pulumi providers T4 (§2) · P6 cadence in the DevOps loop
(SKILL.md "Where it runs") · P7 14-day cooldown on the automerge tier + P11 Monday window
(fleet renovate.json PRs, 2026-09-09; window moved to Saturday 03:00–Sunday 22:00 ET, Lin 2026-09-29) · P8 uv rolling `exclude-newer` (Backend +
containerlab-mcp PRs) · P9 `workflow_dispatch` on backend CI → dropped after Codex P1 (branch copies run with repo secrets); decision issue BE#742 **closed 2026-09-10, Lin: (b) status quo** — pre-merge auth check = local real-Clerk suite, `main` run post-merge (no protected-environment split) · P10 labeling line
in `issue-labeling` · P12 frontend refresh toast keyed on client content — **shipped FE PR#497 + #499, 2026-09-11** (`assetHash` = normalized hash of the built client assets, stamped INSIDE `next build` via `compiler.runAfterProductionCompile` and served first from `/_next/static/version.json` — Vercel captures `public/` before a post-build script runs; prompt only on return after 30 min hidden; `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` pinned in Vercel so builds are byte-stable). Live 04:50Z with `assetHash` on both copies. Six Codex rounds; residuals + revisit triggers on PR#497 · P13 Vercel
Skew Protection — confirmed enabled by Lin 2026-09-09. · P14 security bumps go to the LATEST stable patched version (SKILL.md Always-on; Lin 2026-10-05, "as long as no major break / product concerns") · P15 dev-only semver-major merges on CI green + Codex (§2; Lin 2026-10-05).
