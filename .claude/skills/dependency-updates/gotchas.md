# Gotchas — verified footguns by surface (each line carries its provenance)

**Contents:** 1 Renovate config (fleet template) · 2 pnpm / npm · 3 uv / PyPI · 4 GitHub
Dependabot · 5 Per-package traps · 6 CI and deploy. Every line passed the earned-content
test (`skill-maintenance`): a real event, non-derivable on the spot. Drop a line when its
failure stops reproducing.

## 1. Renovate config (the fleet template — `.github/renovate.json`, identical skeleton)

Skeleton (2026-08-05, `renovate-fleet-policy`): `config:recommended` + `group:allNonMajor`,
`schedule` open from Friday 21:00 America/New_York through Sunday 22:00, the whole weekend
window — never only before it: `prConcurrentLimit: 3` refills only while the schedule is open, so a schedule
that closes Saturday 02:00 strands every entry past the first three under Awaiting Schedule
until the next Friday (Codex, netpilot-skills PR#45, 2026-09-29) — `automergeSchedule` Friday
21:00–Saturday 03:00 ONLY (a T1 automerge inside the window could land during a runtime
ride-out and break single-PR attribution; same review) — `minimumReleaseAge: 7 days`,
`prConcurrentLimit: 3`,
`vulnerabilityAlerts` at any time with `minimumReleaseAge: null`, `automerge: false` and
`vulnerabilityFixStrategy: highest` (P16, 2026-10-06),
one `low-risk-dev` automerge group, approval-gated high-risk deps. New repo = copy it and
`gh api -X PUT repos/lz-networks/<repo>/vulnerability-alerts`. Validate every edit with
`npx --yes --package renovate@latest -- renovate-config-validator <file>` (pin `@latest`: an unpinned
`npx` can run a cached Renovate 37 that rejects current options — §4), then re-trigger the
dashboard's manual-job box and read the regenerated group lines.

- **An automerge rule inheriting `group:allNonMajor` never fires** — one non-automerge
  member disables branch automerge for the whole group. Own `groupName` + `groupSlug`
  required (Codex, fleet PRs 2026-08-05).
- **Overriding `groupName` without `groupSlug` keeps the preset's `all-minor-patch`
  slug** — "separate" groups share one branch (same).
- **`prCreation: "not-pending"` is wrong here** — default `internalChecksFilter: strict`
  already withholds branches during cooldown; with PR-only CI it stalls PR creation
  (same).
- **0.x minors are breaking by semver** — `matchCurrentVersion: "!/^0/"` keeps them out of
  automerge (same).
- **depName-keyed exemptions leak across datasources** — `python` matched the Dockerfile
  image too; scope with `matchDatasources` (same). The only cooldown exemption in the
  fleet is `python` on the `python-version` datasource (no release timestamps → the age
  check can never pass → approval entries held forever).
- **`matchPackageNames` misses runtime deps from pyenv/workflow managers** (`python` →
  `python/cpython`, `node` → `nodejs/node`); gate with `matchDepNames` (BE PR#350/#351,
  2026-08-03).
- **`minimumReleaseAge` set on an automerge rule leaks onto approval-gated deps the same
  rule matches** — Renovate merges every matching `packageRule`; a later gated rule
  overrides `automerge`/grouping but NOT the age, so `typescript`, `eslint`, `ruff`,
  `mypy` (dev deps) silently inherited the tier's 14 days. Every gated rule sets its own
  `minimumReleaseAge` explicitly (Codex P2 on MKT PR#174, 2026-09-09; fixed on BE#740 /
  FE#485 / MKT#174 in the same round).
- **Renovate proposes MAJORS on override security pins** (depType `pnpm.overrides`, or
  `pnpm-workspace.overrides` for a workspace yaml). A major there forces the new major onto
  EVERY consumer, overriding framework ranges — CI green proves nothing (FE#567: `@babel/core`
  `^7`→`^8` under `@vitejs/plugin-react@5`'s `^7`). The FE config disables them, except
  overrides that shadow a direct dependency, which must move in that dependency's own branch
  (FE PR#569, 2026-09-29); 0.x override minors are disabled too (breaking by semver).
  Copy the rule to any repo that carries overrides. The flip side: a disabled pin never
  moves on its own, so the major walk of a package whose dependency an override pins
  (mechanics §3) raises or deletes that override in the same PR (Codex P2, FE PR#569).
- **`vulnerabilityAlerts.automerge` stays false** — open Renovate bug #44065: a
  `[SECURITY]` PR can target an older, still-vulnerable version; the detector is the
  Dependabot alert staying open after merge (fleet policy, 2026-08-05).
- **Resolver-level cooldowns were deferred** (fleet policy, 2026-08-05: pnpm's changes
  local dev resolution; uv's was a fixed date). **The uv trigger has fired** — uv ≥0.9.17
  accepts rolling `exclude-newer` durations, persisted in `uv.lock` as
  `exclude-newer-span`, with `exclude-newer-package` per-package exceptions; the window
  advances only on re-resolution (`uv lock --upgrade[-package]`), never on `uv sync`
  (research 2026-09-08, docs.astral.sh/uv/reference/settings). Renovate does NOT pass
  `--exclude-newer` (renovate #41654 open), so uv enforces the pyproject value when
  Renovate locks: set it equal to `minimumReleaseAge` or Renovate PRs fail to lock, and
  write any security exception into `pyproject.toml` (a CLI-only cutoff is stripped by
  the next plain `uv lock`). Local `uv` is 0.9.2 (2026-09-08) — a uv bump precedes
  adoption. Decision: tiers.md §6.8. pnpm 11 ships its own 24 h default (§2).
- **A grouped framework PR may NOT contain the security member — Renovate SPLITS it out.**
  When a CVE fires for one member of a Renovate group (e.g. `next` in the `nextjs-core`
  group), `vulnerabilityAlerts` opens a SEPARATE minimal `[SECURITY]` PR for the vulnerable
  package (`renovate/npm-<pkg>-vulnerability`) and DROPS it from the group PR — so the group
  PR's title still reads "Update <group> to vX" while its diff bumps only the NON-security
  members. **Before treating any group PR as the CVE fix, grep its package.json diff for the
  VULNERABLE package's OWN line** — a group-title version number is not proof the fix is in
  it. Provenance: pass-905 (2026-10-03) — MKT "nextjs-core" #200 bumped only
  `eslint-config-next`→16.3.6 (NOT `next`); the real fix was the split `next` `[SECURITY]`
  PR #237. Merging #200 as "the next CVE fix" would have shipped a next/eslint-config-next
  version-lock mismatch AND left `next` critical-vulnerable. Codex's version-lock P2 + the
  diff cross-check caught it; the two then merge as a pair (the security split = the one
  runtime, the group remnant = the alignment follow-up, same as FE#587 + FE#572).

## 2. pnpm / npm

- **Renovate's pnpm `[SECURITY]` PRs can ship override keys that mismatch their own
  lockfile serialization** → `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH` on every one, even
  rebased. Do not debug them: supersede with ONE hand PR (range-scoped override +
  `pnpm install --lockfile-only`); the Renovate PRs auto-close when the alerts clear
  (FE PR#308, 2026-08-05: 10 alerts → 0, 5 PRs self-closed).
- **`packageManager` pin is load-bearing** — Renovate, CI (`pnpm/action-setup` reads the
  field; specifying `version:` too errors on mismatch) and local all resolve with one
  pnpm; Renovate tracks the field as the gated dep `pnpm` (FE PR#310 + MKT PR#95,
  2026-08-05). Frontend = pnpm 10.20.0 · marketing = pnpm 11.
- **pnpm 11 is a migration, not a bump** (MKT#107, 2026-08-05; applies verbatim to the
  Frontend's future walk): (1) `package.json` `pnpm.overrides` is SILENTLY ignored —
  every security pin drops until overrides move to `pnpm-workspace.yaml overrides:`;
  (2) the built-in ~24 h `minimumReleaseAge` rejects lockfiles carrying same-day
  transitives (`pnpm clean --lockfile` + fresh install); (3) `allowBuilds` per-dep
  approvals required (set all false = pnpm-10 parity); (4) bump the `packageManager`
  pin in the same PR.
- **Overrides do not steer PEER dependencies** — add the package as a root devDependency
  instead (marketing esbuild through contentlayer2/mdx-bundler, 2026-07-16).
- **An `overrides` caret FLOOR masks a security alert on a transitive dep — Renovate opens
  NO PR for it.** When a transitive package is pinned via a caret override (`dompurify:
  ^3.4.11`) and a Dependabot alert fires on the version the lockfile resolved inside that
  floor (stale at 3.4.13, vulnerable range `3.4.13–3.4.15`), Renovate reads the floor as
  already-satisfied and opens nothing — even security-exempt — so the alert sits with no PR
  path while the lockfile stays on the vulnerable pin. Supersede by hand (ladder step 2):
  bump the override FLOOR above the vulnerable range (`^3.4.16`) + `pnpm install
  --lockfile-only`; **re-resolving without raising the floor keeps the stale pin**. Diff is
  surgical — the floor line + the moved lock entries only. (FE#593/PR#594 dompurify
  3.4.13→3.4.16, GHSA-p98j-92pf-mc4p, 2026-10-04.)
- **`pnpm install --lockfile-only` re-fetches metadata and can add a `deprecated:` line to
  an UNCHANGED entry** (eslint 9.39.4 gained one on FE#482, 2026-09-08) — a lock diff with
  one extra `+ deprecated:` line and no version change is metadata, not a moved package;
  say so in the PR body rather than chasing it.
- **pnpm ≥11.1.3 re-validates the whole lockfile against `minimumReleaseAge` on every
  install** and aborts in CI (`ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION` /
  `ERR_PNPM_NO_MATURE_MATCHING_VERSION`); Renovate writes exact-version
  `minimumReleaseAgeExclude` entries into `pnpm-workspace.yaml` for security fixes
  younger than pnpm's gate (research 2026-09-08, pnpm v11.1.3 release notes, renovate
  PR#40020). Marketing runs pnpm 11.18 — expect that key in its `[SECURITY]` PRs and
  keep it; a hand override-refresh younger than 24 h needs the same entry.
- **Never override a framework's own dependency range** (sharp 0.35 vs next `^0.34.5`)
  — disposition the alert and wait for the framework.
- **`@sentry/nextjs` 10.73.0 breaks vitest** — its `@sentry/server-utils@10.73.0` bundles
  `@apm-js-collab/code-transformer-bundler-plugins`, whose `webpack.mjs` calls
  `fileURLToPath` on a non-file URL under vitest → `ERR_INVALID_URL_SCHEME` / "The URL
  must be of scheme file" in EVERY suite (122 red on FE#338, 2026-09-08). Diagnosed from
  the CI stack frame, not the PR table — pinning all 15 shared transitive moves still
  failed (the bisect), which is what pointed at a LISTED package. No fixed Sentry
  release exists (10.73.0 newest, 2026-08-31): hold `@sentry/nextjs` at 10.68 (ledger
  watch row, trigger = a 10.74+ release), supersede the group with the clean subset.
  **10.72.0 breaks it the same way** (FE#338 regenerated lock, 122 red, run 34352689055,
  2026-09-09) — so the hold is `<10.69.0` AND an exact `10.68.0` pin in package.json: a
  caret let Renovate's lock regeneration move it while package.json showed no diff.
- **After `main` changes a `pnpm.overrides` key, EVERY Renovate branch in that repo fails
  `ERR_PNPM_OUTDATED_LOCKFILE` at install, and ticking the dashboard's rebase box does
  NOT fix it** — FE#337 was regenerated twice (03:08Z, 03:39Z) and mismatched both times
  (Renovate's lock serialization vs our overrides; the same class as the `[SECURITY]`
  mismatch above). Do not debug: supersede with ONE hand PR carrying the same bumps
  (FE dev-tooling PR, 2026-09-09); Renovate's PR auto-closes when its deps are current.

## 3. uv / PyPI

- **`uv lock --upgrade-package X --dry-run` answering `No lockfile changes detected` means a
  cap blocks the move, not that X is current.** Find the capper with `uv tree --package X
  --invert` and read its `requires_dist` on PyPI (cryptography 48 under clerk-backend-api
  `<49`, BE#382, 2026-08-04).
- **Renovate opens nothing for a transitive-only alert on `uv.lock`** (its uv manager
  tracks `pyproject.toml` deps). `pip` 26.1.2 under `pip-audit → pip-api` sat as alert
  #30 from 2026-09-01 with no PR; the surgical bump is the only path (mechanics §6).
- **`uv.lock` carries `upload-time` per artifact** — that is the release-age source for
  hand-made bumps; no network call needed.
- **Backend auth-dep bumps** (`cryptography`, `PyJWT`, `starlette`, `python-multipart`,
  `mcp`, `clerk-backend-api`) are exercised by CI only on `main` (the real-Clerk job
  has no `workflow_dispatch`). Pre-merge = the local real-Clerk suite with `CI=1` and
  `CLAUDE_CODE_OAUTH_TOKEN` exported (`tests/conftest.py` blanks Claude tokens
  locally; `.env.test` lacks the var; without it the app's lifespan aborts every test
  with "No Claude auth configured" — 55 errors, clerk-backend-api 7 lane 2026-09-09) —
  BE PR#149, 2026-07-16. Recipe that passed 55/55: the unit job's literal env + Clerk
  keys from the env files + `DATABASE_URL` from `.env.test` (the LOCAL test DB — never
  `.env`'s Neon DSN) + `CI=1`, then the integration job's exact pytest line.
  `clerk-backend-api` is a test fixture only; prod auth = PyJWT + JWKS.
- **A test step piped through `| tail` cannot fail the chain** — "Failed to spawn: pytest"
  (fresh worktree synced without `--all-groups`, `dev-workflow/setup.md`) printed as the
  last line and the chain went on to open the PR with an unproven claim (svix lane,
  2026-09-09). Test the exit status (`set -o pipefail` + `|| return 1`), never the tail.
- **Deliberate `==` pins are walked, never carried**: `fastapi`, `uvicorn`, `sse-starlette`
  (BE#110) and the `claude-agent-sdk` narrow range (billing) — a security PR must not
  move them incidentally (BE PR#149).

## 4. GitHub Dependabot

- **Alert lists lag merges by one scan cycle** — verify against the lockfile on `main`.
- **Dismissed alerts never reopen on their own** when a patch appears — only auto-triage-
  rule dismissals do; a manual one stays dismissed (research 2026-09-08,
  docs.github.com dependabot-alerts). The ledger's dismissal row is the only path back
  (ladder step 5). The dismissal comment is capped at 280 chars (`alert.sh` enforces).
- **Renovate's `[SECURITY]` PR targets the HIGHEST version fleet-wide** (`vulnerabilityAlerts.
  vulnerabilityFixStrategy: highest`, P16, 2026-10-06 — Renovate's default is `lowest`, the
  earliest fixed version). The option is valid ONLY nested under `vulnerabilityAlerts`; top-level
  it fails `renovate-config-validator`, and an `npx` cache can hand you Renovate 37, which rejects
  the option outright — validate with `npx --yes --package renovate@latest -- renovate-config-validator`
  (P16 PRs, 2026-10-06). A security PR can now carry a larger jump than a patch; the pass's
  pre-merge read (SKILL.md Always-on) is the control.
- **`vulnerability-alerts` is a repo setting, not a file** — `PUT` enables, `GET` → 204
  enabled / 404 not (BE#103, 2026-07-14). Dependabot security *updates* stay off:
  Renovate's `vulnerabilityAlerts` opens the fix PRs (no duplicates).
- **A tracking issue's trigger is only as good as its re-check** — BE#382 said "re-check
  on any Clerk SDK bump"; the unblocking release (clerk-backend-api 7.0.0, 2026-08-11,
  `cryptography<51`) fired no bump and nobody looked for 4 weeks. Triggers live in the
  ledger and are checked every pass (SKILL.md step 2).

## 5. Per-package traps

- **`posthog-js`** — behavior frozen by `defaults: "2026-01-30"` in
  `instrumentation-client.ts`; leave the pin alone on bumps (FE#282, 2026-08-05).
- **`@assistant-ui/store` is PATCHED** (`pnpm patch`, FE PR#422, 2026-09-01) — any
  assistant-ui bump silently drops the patch (`patchedDependencies` is version-keyed);
  the failing-without-patch test turns that into a CI failure. Re-verify the patch and
  the unstable-API canary on every assistant-ui bump (`composer-typing-lag` arc).
- **`contentlayer2` 0.5.8 hard-peers OTel 1.x** — forcing `@opentelemetry/core` 2.x breaks
  `next build`; marketing's OTel alert is dismissed `not_used` (build-time only);
  revisit when contentlayer2 ships OTel-2 support (2026-07-16).
- **`clerk-backend-api` 6→7 lifts the cryptography cap to `<51`** (7.0.0, 2026-08-11) —
  the fix for BE#382 is that major (T4) plus `cryptography` 50.x in one PR; run the
  local real-Clerk suite first (§3).
- **`svix`** — the Clerk webhook verifier; a bump touches org/seat event intake (billing-
  adjacent, T4 per tiers.md §2). 2.2.0's breaking notes are JS/PHP-only (BE#507 body).
- **The backend README's Stack table restates the `==` pins** (uvicorn, SQLAlchemy, Alembic,
  sse-starlette) — a runtime bump PR updates it in the same commit or Codex flags it
  (P2 on BE#743, 2026-09-09).
- **`sqlalchemy` patch bumps ship first and alone** — the asyncpg cancellation /
  poisoned-pool class (NETPILOT-BACKEND-K/-4K/-4M) was fixed by one; keep them isolated
  so a regression is attributable (July 2026 audit, FE#58 comment).
- **`claude-agent-sdk` couples `mcp`** — the `mcp <2` pin exists for CVE-2025-66416 and
  for the SDK's own range; `mcp` majors go through `sdk-upgrade-adoption`, never alone
  (BE PR#717 autoclosed 2026-09-08).
- **`astral-sh/setup-uv` v10 disables caching only for `pull_request_target`,
  `workflow_run`, `release` events** — the backend workflow uses `push` + `pull_request`,
  so the bump is behavior-neutral for us (BE#578 body, read 2026-09-08). Still T4 (CI
  file).
- **`haproxy` (NetPilot-2-LB Dockerfile image — the fleet LB, T4, max blast radius)** — the
  merge gate is `haproxy -c` on the NEW image first (mechanics §8), but the config is a
  TEMPLATE (`haproxy.cfg.template`, rendered at boot by `entrypoint.sh`): render it before
  validating — substitute the `@@BACKEND_SERVER_LINES@@` placeholder with a sample
  `server be1 10.0.0.1:8080 check inter 2s fall 5 rise 2 cookie srv1` line and set
  `LB_REPLICA_ID` (the `log-format` uses `%[env(LB_REPLICA_ID)]`), then
  `docker run --rm -e LB_REPLICA_ID=x -v <dir>:/cfg haproxy:<ver>-alpine haproxy -c -f /cfg/haproxy.cfg`.
  Validate the CURRENT tag too as a baseline — identical output (one expected `log-format`
  overrides `option httplog` warning) ⇒ no removed/changed directives. macOS Docker can't
  bind-mount `/tmp` (use a `/Users/…` path). LB has NO CI → the merge needs the no-CI
  `local-check: <head7> …` body attestation naming this check (dev-workflow/merge.md), and
  the post-deploy CORS-preflight + sticky-cookie probes run immediately (mechanics §8). A
  multi-feature-version jump (e.g. 3.0 LTS → 3.4) still self-merges T4 when `haproxy -c` +
  the changelog + both probes are clean (3.0.25→3.4.6, pass-917 2026-10-04).

## 6. CI and deploy

- **The fleet spans two GitHub owners** — `containerlab-mcp` lives under `netpilot-labs`, the
  four app repos under `lz-networks`; every script resolves the owner via `owner_of` (a wrong
  owner reads as "no alerts, no PRs, no dashboard" — the clab column was blind through the
  first two passes, 2026-09-09).
- **Renovate PRs are non-draft** — CI runs on open and on every rebase; the draft-gating
  that `dev-workflow` relies on for Codex-free rounds does not apply. Codex must be
  requested explicitly (mechanics §2).
- **A grouped PR's merge deploys N bumps at once** — attribution of a post-merge signal
  needs the audit lines on the PR; when in doubt, the revert takes the whole group and the
  re-attempt splits it.
- **Vercel's Ignored Build Step is not a way to skip dependency deploys** — a canceled
  build still counts as a deployment, a lockfile-only commit CAN change the built output,
  and skipping leaves `main` ahead of production until an unrelated deploy silently ships
  it (breaks "every merge is a watched deploy"). Suppress the frontend's refresh TOAST
  (ledger P12), never the deploy (research 2026-09-08, vercel.com/docs project-settings +
  monorepos "skipping unaffected projects").
- **Backend `postgres` images (compose 17-alpine, CI service 16-alpine) trail Neon
  17.10** — the CI service is a major behind prod; the pending `postgres 18` approval
  would put both AHEAD of prod. Align to 17, never 18, until Neon moves (read
  2026-09-08).

## 7. Pass scheduling — the weekend window

- **Decide "is this a window pass?" from `date`, never from a handover sentence.** The rule
  (SKILL.md "Where it runs"): the window opens Friday 21:00 America/New_York for Renovate's
  T1 automerge; the loop's FULL pass is the first pass on/after Saturday 03:00; later passes
  through Sunday 22:00 are window passes; the loop's merges land ONLY in those passes (T0
  security excepted). Two mechanical checks: (1) `TZ=America/New_York
  date +%u` is `6` with hour ≥ 03, or `7` with hour < 22; (2) the FULL pass (inventory +
  queue build) runs **at most once per ISO week**, the week read as `TZ=America/New_York
  date +%G-%V` (bare UTC `date +%V` rolls to the next week during the Sunday-evening passes
  and would make the next Saturday look already run — Codex, netpilot-skills PR#45) — a window
  pass whose ledger §1 snapshot already carries this week's full pass CONTINUES that queue,
  it does not rebuild one. Outside the window this is a steps-1–2-only pass — plus, and
  only, the two named duties: the Sunday 23:00 ET pass reads the last ride-outs, the Monday
  01:00 ET closeout runs steps 7–9 (desk lines, ledger stamp, weekend report) with NO
  merges; do NOT declare a full pass or build a merge queue.
  **Provenance:** pass-699/700 (2026-09-15, a **Tuesday**) mislabeled the day "Mon 09-15"
  in their worklogs (calendar rolled Mon→Tue between pass-698 23:12 ET and pass-699 01:13 ET;
  the day-of-week string was never recomputed), and pass-700 — trusting pass-699's handover
  prose instead of `date` — declared a SECOND full pass due and queued out-of-window walks the
  real Monday (Sept 14, passes 688–690) had already deferred to the next week. No merge landed
  (the queue was caught + voided by pass-701), but a blind execution would have shipped
  T3/T4 deploys outside the window. The handover text is a hint; `date` + the ledger week are
  the authority.
